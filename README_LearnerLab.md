# GOAD を AWS Academy Learner Lab で動かす（自主練習用）

Active Directory の攻撃演習環境 GOAD-Light（Windows 3 台＋踏み台 Linux 1 台）を、自分の Learner Lab 上に構築する手順です。
このブランチ（`learnerlab`）は、Learner Lab の制約（us-east-1・予算 $50）に合わせて次の点を変更しています。

- AMI をリージョンに依存せず自動検索（元は eu-west-3 固定）
- 踏み台への SSH を自分の IP だけに制限（元は全世界に公開）
- 構築後に **NAT Gateway を自動削除**（停止中も 1 日約 $1 かかるため）
- 補助スクリプト `goad-ll.sh`

> [!CAUTION]
> - GOAD は **わざと脆弱に作られた環境** です。演習対象はこのラボだけにしてください。他人・学外のシステムへの試行は不正アクセス禁止法違反になります。
> - Learner Lab は **予算を超えるとアカウントが無効化され、全データが消えます**。画面の残高表示は 8〜12 時間遅れます。

---

## 0. 費用の目安（GOAD-Light, 概算）

| 状態 | 費用 |
|---|---|
| 構築（初回 2〜3 時間） | 約 $1 |
| 演習中（全台起動） | 約 $0.25 / 時間 |
| 停止中（ディスク約 120GB＋固定 IP） | 約 $0.5 / 日（約 $3.6 / 週） |
| ラボ削除後 | $0 |

例：6 週間ラボを残して 30 時間練習 → 約 $1 + $22 + $7.5 ≒ **$31**。
**2 週間以上使わないときは `destroy` で削除** し、必要になったら作り直すのが安全です。
`./goad-ll.sh status` でいつでも概算を確認できます。

> [!WARNING]
> Learner Lab は **Start Lab を押すと、停止していたインスタンスを自動で起動** します。
> 他の授業で Learner Lab を開いたときも GOAD が起動して課金されるので、練習しない日は起動直後に `./goad-ll.sh stop` を実行してください。

---

## 1. 自分の PC の準備（初回のみ）

Linux / macOS、または Windows の WSL（Debian/Ubuntu）で作業します。

```bash
# Ubuntu / Debian の例
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip wget unzip openssh-client
# terraform（https://developer.hashicorp.com/terraform/install の手順でも可）
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
```

GOAD（Learner Lab 版）を取得して、初回セットアップを行います。

```bash
git clone -b learnerlab <配布されたリポジトリURL> GOAD
cd GOAD
./goad.sh -t check -l GOAD-Light -p aws   # 初回は Python 環境の作成に数分かかります
```

> Python 3.14 以降の環境では ansible が動きません。3.11〜3.13 を使ってください（授業 Web の補足を参照）。

## 2. Learner Lab の起動と認証情報の登録（毎回）

1. Learner Lab で **Start Lab** を押し、表示が緑になるまで待つ
2. **AWS Details** → **AWS CLI: Show** の内容をコピー
3. 次を実行して貼り付け、最後に `Ctrl-D`

```bash
./goad-ll.sh creds
```

認証情報はセッションごとに変わります。**Start Lab を押すたびに再登録** してください。

## 3. 初期設定（初回のみ）

```bash
./goad-ll.sh setup
```

自分のグローバル IP が自動で表示されるので、そのまま Enter を押します。
学内と自宅など **接続元が変わったら**、ラボ作成前は `setup` をやり直し、作成後は `./goad-ll.sh allow-ip` を実行します（`ssh` がタイムアウトする場合はまずこれを確認）。

## 4. ラボの構築（初回のみ・2〜3 時間）

```bash
./goad-ll.sh install
```

- 途中でセッションの残り時間が少なくなったら、Learner Lab の **Start Lab をもう一度押す** と延長されます。
- 完了すると NAT Gateway が自動削除され、状態が表示されます。

**途中で失敗したとき**：まず `./goad-ll.sh creds` で認証情報を再登録し、続きから再実行します。

```bash
./goad.sh
# GOAD のコンソールで:
load <インスタンスID>        # status で表示される ID
provision_lab               # Windows 側の設定を続きから再実行
exit
./goad-ll.sh nat-off
```

> provision_lab の前に NAT が必要な場合（Windows がインターネットに出られない旨のエラー）は `./goad-ll.sh nat-on` を先に実行してください。

## 5. 演習（毎回）

```bash
./goad-ll.sh creds     # Start Lab 後に毎回
./goad-ll.sh start     # 停止していれば起動（数分待つ）
./goad-ll.sh ssh       # 踏み台にログイン → ここから攻撃ツールを実行
```

ラボのネットワーク：

| ホスト | IP | 役割 |
|---|---|---|
| kingslanding (DC01) | 192.168.56.10 | sevenkingdoms.local の DC |
| winterfell (DC02) | 192.168.56.11 | north.sevenkingdoms.local の DC |
| castelblack (SRV02) | 192.168.56.22 | IIS / MSSQL サーバ |
| jumpbox | 192.168.56.100 | 攻撃用の踏み台（Ubuntu） |

> AWS 上では **LLMNR / NBT-NS ポイズニング（Responder など）は動作しません**。これらは授業のデモ環境で扱います。

**終わったら必ず停止：**

```bash
./goad-ll.sh stop
./goad-ll.sh status    # すべて stopped / NAT Gateway なし を確認
```

## 6. 片付け

```bash
./goad-ll.sh destroy
```

または Learner Lab の **Reset**（アカウント内のすべてが消えます）。

---

## 良い攻撃手順ができたら

授業用のデモ環境は同じ GOAD-Light です（ユーザー・パスワード・脆弱性の構成は共通）。
再現できるよう **実行したコマンドと結果のメモ** を残しておき、授業で発表してください。

## コマンド一覧

| コマンド | 内容 |
|---|---|
| `./goad-ll.sh setup` | 初期設定（リージョン・SSH 許可 IP） |
| `./goad-ll.sh creds` | Learner Lab の認証情報を登録 |
| `./goad-ll.sh install [LAB]` | 構築（既定 GOAD-Light）＋NAT 削除 |
| `./goad-ll.sh status` | 状態と概算費用 |
| `./goad-ll.sh start` / `stop` | 全台の起動 / 停止 |
| `./goad-ll.sh ssh` | 踏み台へ SSH |
| `./goad-ll.sh allow-ip` | 接続元 IP が変わったときの SSH 許可の更新 |
| `./goad-ll.sh nat-off` / `nat-on` | NAT Gateway の削除 / 再作成（再プロビジョニング時） |
| `./goad-ll.sh destroy` | ラボの完全削除 |
