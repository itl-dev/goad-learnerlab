#!/usr/bin/env bash
# goad-ll.sh : AWS Academy Learner Lab で GOAD を使うための補助スクリプト
#
#   ./goad-ll.sh setup          初期設定（リージョン us-east-1・SSH 許可元 IP を goad.ini に設定）
#   ./goad-ll.sh creds          Learner Lab の「AWS Details > AWS CLI」の内容を貼り付けて認証情報を登録
#   ./goad-ll.sh install [LAB]  ラボ構築（既定 GOAD-Light）。完了後に NAT Gateway を自動削除
#   ./goad-ll.sh status         ラボのインスタンス状態と概算費用を表示
#   ./goad-ll.sh stop|start     ラボの全インスタンスを停止 / 起動
#   ./goad-ll.sh nat-off|nat-on NAT Gateway の削除 / 再作成（再プロビジョニング時のみ nat-on）
#   ./goad-ll.sh allow-ip       接続元 IP が変わったときに踏み台への SSH 許可を更新
#   ./goad-ll.sh ssh            踏み台（jumpbox）へ SSH
#   ./goad-ll.sh destroy        ラボを完全に削除（費用ゼロに戻す）
set -euo pipefail

cd "$(dirname "$0")"
GOAD_DIR=$(pwd)
VENV="$HOME/.goad/.venv"
INI="$HOME/.goad/goad.ini"
REGION=us-east-1
ZONE=us-east-1a

die() { echo "[-] $*" >&2; exit 1; }
info() { echo "[*] $*"; }

need_venv() {
  [ -d "$VENV" ] || die "先に ./goad.sh を一度実行して環境を作成してください"
  command -v terraform >/dev/null || die "terraform が見つかりません（README_LearnerLab.md 参照）"
}

# workspace 内の AWS インスタンスを 1 つ特定
instance_dir() {
  local d
  d=$(ls -d workspace/*-aws 2>/dev/null | head -n1 || true)
  [ -n "$d" ] || die "AWS のラボがまだありません（./goad-ll.sh install）"
  echo "$d"
}
instance_id() { basename "$(instance_dir)"; }

py() { "$VENV/bin/python" -I - "$@"; }

ini_set() { # section key value
  "$VENV/bin/python" -I - "$INI" "$1" "$2" "$3" <<'EOF'
import configparser, sys
path, sec, key, val = sys.argv[1:]
c = configparser.ConfigParser(); c.read(path)
if not c.has_section(sec): c.add_section(sec)
c.set(sec, key, val)
with open(path, 'w') as f: c.write(f)
EOF
}

ask_cidr() { # 許可する接続元 IP を尋ねて goad.ini に保存し、値を返す
  local myip cidr
  myip=$(wget -qO- https://checkip.amazonaws.com | tr -d '[:space:]' || true)
  read -r -p "踏み台への SSH を許可する IP/CIDR [${myip:+$myip/32}]: " cidr </dev/tty
  cidr=${cidr:-${myip:+$myip/32}}
  [ -n "$cidr" ] || die "IP を取得できませんでした。手動で入力してください"
  ini_set aws whitelist_cidr "$cidr" >&2
  echo "$cidr"
}

cmd_setup() {
  need_venv
  [ -f "$INI" ] || ./goad.sh -t check -l GOAD-Light -p aws >/dev/null 2>&1 || true
  [ -f "$INI" ] || die "$INI が作成されていません"
  local cidr; cidr=$(ask_cidr)
  ini_set aws aws_region "$REGION"
  ini_set aws aws_zone "$ZONE"
  info "goad.ini を更新: region=$REGION zone=$ZONE whitelist_cidr=$cidr"
  info "接続元が変わったら（学内⇔自宅など）、ラボ作成後は ./goad-ll.sh allow-ip で更新してください"
}

cmd_allow_ip() { # 作成済みラボのセキュリティグループを更新
  need_venv
  local cidr; cidr=$(ask_cidr)
  tf apply -auto-approve -input=false -var "whitelist_cidr=[\"$cidr\"]" \
    -target=aws_vpc_security_group_ingress_rule.allow_whitelist_ingress
  info "踏み台への接続許可を $cidr に更新しました"
}

cmd_creds() {
  echo "Learner Lab の『AWS Details』→『AWS CLI: Show』の内容を貼り付け、最後に Ctrl-D を押してください:"
  local raw; raw=$(cat)
  local ak sk st
  ak=$(sed -n 's/^aws_access_key_id *= *//p' <<<"$raw" | tr -d '\r')
  sk=$(sed -n 's/^aws_secret_access_key *= *//p' <<<"$raw" | tr -d '\r')
  st=$(sed -n 's/^aws_session_token *= *//p' <<<"$raw" | tr -d '\r')
  [ -n "$ak" ] && [ -n "$sk" ] && [ -n "$st" ] || die "認証情報を読み取れませんでした"
  mkdir -p ~/.aws; touch ~/.aws/credentials ~/.aws/config; chmod 600 ~/.aws/credentials
  "$VENV/bin/python" -I - "$ak" "$sk" "$st" <<'EOF'
import configparser, os, sys
ak, sk, st = sys.argv[1:]
p = os.path.expanduser('~/.aws/credentials'); c = configparser.ConfigParser(); c.read(p)
c['goad'] = {'aws_access_key_id': ak, 'aws_secret_access_key': sk, 'aws_session_token': st}
with open(p, 'w') as f: c.write(f)
p = os.path.expanduser('~/.aws/config'); c = configparser.ConfigParser(); c.read(p)
c['profile goad'] = {'region': 'us-east-1'}
with open(p, 'w') as f: c.write(f)
EOF
  info "プロファイル [goad] を登録しました（セッションごとに再登録が必要です）"
}

tf() { # terraform を instance の provider ディレクトリで実行
  local d; d="$(instance_dir)/provider"
  AWS_PROFILE=goad terraform -chdir="$d" "$@"
}

cmd_nat() { # on|off
  need_venv
  local flag=true; [ "$1" = off ] && flag=false
  info "NAT Gateway を $( [ "$flag" = true ] && echo 作成 || echo 削除 ) します"
  tf apply -auto-approve -input=false -var "enable_nat=$flag" \
    -target=aws_route_table.goad_private_table -target=aws_nat_gateway.nat_gateway -target=aws_eip.nat_ip
}

cmd_install() {
  need_venv
  local lab=${1:-GOAD-Light}
  grep -q '^whitelist_cidr' "$INI" 2>/dev/null || die "先に ./goad-ll.sh setup を実行してください"
  info "$lab を AWS に構築します（1.5〜3 時間程度。途中でセッションが切れそうなら Start Lab を押して延長）"
  yes y | ./goad.sh -t install -l "$lab" -p aws -m remote || {
    echo; info "構築が途中で失敗しました。よくある対処:"
    echo "    1) セッション切れなら creds を再登録"
    echo "    2) ./goad.sh を起動し 'load $(instance_id 2>/dev/null || echo "<id>")' → 'provision_lab' で続きから再実行"
    exit 1; }
  cmd_nat off
  info "構築完了。NAT Gateway を削除しました（以降の演習には不要です）"
  cmd_status
}

cmd_status() {
  need_venv
  local id; id=$(instance_id)
  AWS_PROFILE=goad py "$id" <<'EOF'
import boto3, sys
lab_suffix = sys.argv[1]   # 例: dabb92-goad-light-aws（Lab タグは <LAB名>-<instance_id>）
ec2 = boto3.Session(region_name='us-east-1').client('ec2')
r = ec2.describe_instances(Filters=[{'Name':'tag:Lab','Values':[f'*-{lab_suffix}']}])
vol_ids = []
# 概算単価（us-east-1, オンデマンド, USD/h）。実際の請求は AWS の料金ページで確認すること
price = {('t2.medium','windows'):0.0644, ('t2.medium','linux'):0.0464}
run = 0.0
print(f"{'Name':32} {'Type':10} {'State':10} {'Private IP':14} Public IP")
for res in r['Reservations']:
    for i in res['Instances']:
        if i['State']['Name'] == 'terminated': continue
        name = next((t['Value'] for t in i.get('Tags',[]) if t['Key']=='Name'), i['InstanceId'])
        osk = 'windows' if i.get('Platform') == 'windows' else 'linux'
        if i['State']['Name'] == 'running': run += price.get((i['InstanceType'],osk), 0.07)
        vol_ids += [b['Ebs']['VolumeId'] for b in i.get('BlockDeviceMappings', []) if 'Ebs' in b]
        print(f"{name:32} {i['InstanceType']:10} {i['State']['Name']:10} {i.get('PrivateIpAddress',''):14} {i.get('PublicIpAddress','')}")
nat = [n for n in ec2.describe_nat_gateways(Filter=[{'Name':'state','Values':['available','pending']}])['NatGateways']
       if any(t['Key']=='Lab' and t['Value'].endswith(lab_suffix) for t in n.get('Tags',[]))]
gb = sum(v['Size'] for v in ec2.describe_volumes(VolumeIds=vol_ids)['Volumes']) if vol_ids else 0
print()
print(f"NAT Gateway: {'あり（$0.045/h 課金中。構築後は nat-off）' if nat else 'なし'}")
print(f"起動中の概算: ${run + (0.045 if nat else 0) + 0.005:.2f}/時間")
print(f"停止中も発生する概算: ディスク約{gb}GB + 固定IP ≒ ${gb*0.10/30 + 0.12:.2f}/日")
EOF
}

cmd_power() { # stop|start
  need_venv
  ./goad.sh -t "$1" -i "$(instance_id)"
}

cmd_ssh() {
  need_venv
  local d ip; d=$(instance_dir)
  ip=$(tf output -raw ubuntu-jumpbox-ip)
  exec ssh -i "$d/ssh_keys/ubuntu-jumpbox.pem" -o StrictHostKeyChecking=accept-new "goad@$ip"
}

cmd_destroy() {
  need_venv
  read -r -p "ラボ $(instance_id) を完全に削除します。よろしいですか？ (yes/N): " a
  [ "$a" = yes ] || exit 0
  yes y | ./goad.sh -t destroy -i "$(instance_id)"
}

case "${1:-}" in
  setup) cmd_setup ;;
  creds) cmd_creds ;;
  install) shift; cmd_install "$@" ;;
  status) cmd_status ;;
  stop|start) cmd_power "$1" ;;
  nat-off) cmd_nat off ;;
  nat-on) cmd_nat on ;;
  allow-ip) cmd_allow_ip ;;
  ssh) cmd_ssh ;;
  destroy) cmd_destroy ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
