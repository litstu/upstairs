#!/usr/bin/env bash
# ============================================================================
#  Life is Tech! WebS AI セットアップスクリプト
# ----------------------------------------------------------------------------
#  Cloud9 / Mac で Claude Code を AI 共通基盤ゲートウェイ経由で使えるように
#  する。中高生メンバーは、メンターから配られた「AI の接続情報（4 点セット）」を
#  1 つずつ入れるだけで OK。あとは裏で：
#    1. 4 点セットを入力・保存（① 接続先URL ② アクセスキー ③ Claude Codeモデル名 ④ APIモデル名）
#         ① AI_GATEWAY_URL   → ANTHROPIC_BASE_URL
#         ② AI_GATEWAY_KEY   → ANTHROPIC_AUTH_TOKEN
#         ③ Claude Code モデル名（"sonnet" を含む）→ ANTHROPIC_MODEL
#         ④ API モデル名（"haiku" を含む）→ ANTHROPIC_SMALL_FAST_MODEL ＋ AI_GATEWAY_MODEL（サービス用）
#    2. ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL / ANTHROPIC_SMALL_FAST_MODEL /
#       AI_GATEWAY_MODEL を export
#    3. Claude Code の初回対話画面（テーマ / 信頼 / 権限）を先回りでスキップ
#    4. ルール系ファイルを chmod 444 で読み取り専用化
#    5. Claude Code を起動
#
#  ※ 初回は 4 点セット（接続先URL / アクセスキー / Claude Codeモデル名 / APIモデル名）をすべて
#     メンター配布値で入力する（必須・固定しない）。③は "sonnet" を、④は "haiku" を含むことを検証し、
#     貼り違えを防ぐ。メンター配布値にしたことで、URL やモデルが変わってもスクリプトを配り直さず、
#     メンターが新しい値を伝えるだけで直せる（2 回目以降は保存済みの値でサイレントに再ログイン）。
#
#  ■ 初回（メンター同席で 1 回だけ・対話）:
#      source <repo>/member-scripts/lit-webs-ai.sh
#    入力した 4 点セットは ~/.lit-webs-ai/credentials に保存される。
#
#  ■ 2 回目以降・インスタンス再起動後（完全無人）:
#    ~/.bashrc または ~/.zshrc の末尾に次の 1 行を仕込む。保存済みの 4 点セット（キー/URL/2モデル）を
#    無言で再 export するだけなので、ターミナルを開いた瞬間に Claude が使える
#    （バナー／メニュー／クイズは出ない・入力待ちもしない）。
#      WEBS_AI_REFRESH=1 source <repo>/member-scripts/lit-webs-ai.sh
#    保存情報が無い場合は何もせず静かに抜ける（初回は上の対話セットアップを 1 回行う）。
# ============================================================================

# 注意：`set -u` は付けない。
# このスクリプトは `source` で読まれるので、`set -u` を残すと呼び出し元
# シェル（zsh の Powerlevel9k 等）が未定義変数で連続エラーを吐いてしまう。
# 代わりに参照箇所で `${VAR:-}` を使ってデフォルト値を補完する。

# ---------- カラー定義 ----------
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"
MAGENTA="${ESC}[35m"
CYAN="${ESC}[36m"
WHITE="${ESC}[37m"
PINK="${ESC}[38;5;205m"
ORANGE="${ESC}[38;5;208m"
PURPLE="${ESC}[38;5;141m"

# ---------- バナー ----------
print_banner() {
  echo
  printf "%b" "${PINK}${BOLD}"
  cat <<'EOF'
  ╦  ╦╔═╗╔═╗  ╦╔═╗  ╔╦╗╔═╗╔═╗╦ ╦ ┃   ╦ ╦╔═╗╔╗ ╔═╗  ╔═╗╦
  ║  ║╠╣ ║╣   ║╚═╗   ║ ║╣ ║  ╠═╣ ┃   ║║║║╣ ╠╩╗╚═╗  ╠═╣║
  ╩═╝╩╚  ╚═╝  ╩╚═╝   ╩ ╚═╝╚═╝╩ ╩ •   ╚╩╝╚═╝╚═╝╚═╝  ╩ ╩╩
EOF
  printf "%b" "${RESET}"
  printf "%b\n" "${CYAN}${BOLD}            Web サービスプログラミングコース${RESET}"
  printf "%b\n" "${PURPLE}            ✦  AI セットアップ  ✦${RESET}"
  echo
}

step() {
  printf "%b\n" "${BLUE}▸${RESET} ${BOLD}$1${RESET}"
}

ok() {
  printf "%b\n" "  ${GREEN}✓${RESET} $1"
}

warn() {
  printf "%b\n" "  ${YELLOW}!${RESET} $1"
}

fail() {
  printf "%b\n" "  ${RED}✗${RESET} $1"
}

dim() {
  printf "%b\n" "  ${DIM}$1${RESET}"
}

# ---------- 接続確認（キーが本当にゲートウェイで通るか確かめる） ----------
# 現在の ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN を使って /v1/messages へ
# 軽量な POST を投げ、HTTP ステータスだけで判定する（モデルは呼ばれない＝課金ゼロ）。
#   - 401 / 403 → "auth"  : キーが失効/無効/未登録、または接続先 URL がそのキーの
#                            キーストアと一致していない（オーソライザーが Deny）。
#   - 000 / 空   → "neterr": ネットワーク不通など（キーの問題とは断定できない）。
#   - それ以外   → "ok"    : オーソライザーは通過（空ボディなら 400 が返る＝正常）。
#   - curl 不在  → "skip"  : 確認できないので成功扱い（ブロックしない）。
webs_validate_key() {
  command -v curl >/dev/null 2>&1 || { printf 'skip'; return 0; }
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN:-}" "${ANTHROPIC_BASE_URL}/v1/messages" 2>/dev/null)"
  case "$code" in
    401|403) printf 'auth' ;;
    000|"")  printf 'neterr' ;;
    *)       printf 'ok' ;;
  esac
}

# ---------- ログアウト（webs-logout コマンド本体） ----------
# 保存済みアクセスキーと、現在のシェルの AI 接続用環境変数をリセットする。
# クイズ合格フラグ（$WEBS_AI_QUIZ_PASS_FILE）は残すので、再ログイン時に
# 説明・クイズはスキップされる。
# source で読み込まれている前提なので、この関数も現在のシェルに残り、
# `webs-logout` でいつでも呼べる。
webs-logout() {
  echo
  printf "%b\n" "  ${PINK}${BOLD}👋 ログアウト${RESET}"
  echo

  # 保存済みアクセスキーを削除
  if [ -f "$WEBS_AI_CRED_FILE" ]; then
    rm -f "$WEBS_AI_CRED_FILE"
    printf "%b\n" "  ${GREEN}✓${RESET} 保存されてたログイン情報を消したよ"
  else
    printf "%b\n" "  ${DIM}・ ログイン情報は保存されてなかったよ${RESET}"
  fi

  # 現在のシェルの環境変数をクリア
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_AUTH_TOKEN
  unset ANTHROPIC_MODEL
  unset ANTHROPIC_SMALL_FAST_MODEL
  unset AI_GATEWAY_MODEL
  unset WEBS_AI_INITIALIZED
  unset WEBS_AI_ACCESS_KEY
  unset WEBS_AI_GATEWAY_URL
  unset WEBS_AI_MODEL_ID
  unset WEBS_AI_SMALL_FAST_MODEL_ID

  printf "%b\n" "  ${GREEN}✓${RESET} 今のシェルの AI 接続情報もリセットしたよ"

  echo
  printf "%b\n" "  ${WHITE}またね〜！次にシェルを開いたときに、もう一回ログインしてね 🌟${RESET}"
  printf "%b\n" "  ${DIM}（クイズ合格はそのまま残ってるから、次回もスキップされるよ）${RESET}"
  echo
}

# ---------- 設定（環境ごとに上書き可） ----------
# 下記はメンター側で値を埋めて配布する想定
# ハードコード値（メンター側で配布前に書き換える）
WEBS_AI_DEFAULT_REGION="ap-northeast-1"
# 接続先は Regional API Gateway 直結（CloudFront は経由しない）。
# 理由: CloudFront はオリジン応答タイムアウトが最大 60 秒で、サブエージェント等の長い推論
# （非ストリームで ~45 秒以上）が最初のバイトを 30 秒以内に返せず 504（OriginCommError）に
# なっていた。API Gateway（Regional）は STREAM/最大 15 分・アイドル 5 分のため、直結なら
# 長時間の推論も通る。CloudFront を介さない分の WAF はステージへ関連付けた Regional WebACL
# （IpReputation / KnownBadInputs / CommonRuleSet + IP レート + Geo(JP)）が同等の入口保護を
# 提供し、認証は Lambda Authorizer（無効アクセスキーは 401/403）が担う。
#
# 本番はカスタムドメイン `aigateway-api.life-is-tech.com`（Regional API Gateway に BasePathMapping
# 空パスで紐付け済み）。`/v1/*` を直接叩けば `stage=prod` の `/v1/*` に到達する
# （`/prod` プレフィックスは BasePathMapping が吸収）。カスタムドメインを使うので API 再作成で
# ID が変わっても DNS 側で追従でき、配布物を配り直さなくて済む。
#
# 環境切替（メンター/開発者向け）:
#   WEBS_AI_ENV=dev source lit-webs-ai.sh   → dev 環境の直結 URL を既定値に
#   （省略時）source lit-webs-ai.sh          → prod カスタムドメイン（メンバー配布はこちら）
#
# 保存済み URL（メンター配布値・$WEBS_AI_CRED_FILE の WEBS_AI_GATEWAY_URL）があればそれが最優先で、
# 下記既定値はあくまで初回セットアップ時のフォールバック。メンターが dev で試したいときは
# `webs-logout` で一度クリアしてから `WEBS_AI_ENV=dev source ...` で入り直す。
case "${WEBS_AI_ENV:-prod}" in
  dev)
    # 開発 API GW（Regional 直結）。API 再作成で ID が変わり得るのでメンバー配布用ではなく
    # メンター/開発者の内部確認用。ID 変更時はこの既定値を書き換える（またはメンター配布値で運用）。
    WEBS_AI_DEFAULT_GATEWAY_BASE_URL="https://pza730emsb.execute-api.ap-northeast-1.amazonaws.com/prod"
    ;;
  *)
    # 本番カスタムドメイン（安定 URL・basePath 空）。DNS は上位ドメイン管理者側で管理されており、
    # ARN が変わっても手動更新は要らない前提。
    WEBS_AI_DEFAULT_GATEWAY_BASE_URL="https://aigateway-api.life-is-tech.com"
    ;;
esac
# Claude Code に送らせるモデル（フル推論プロファイル ID）。
# このゲートウェイの許可リストはフル ID（global.anthropic.claude-...）で持っているため、
# Claude Code 既定の短縮名（claude-sonnet-4-6 等）のままだと「許可されていません」で 403 になる。
# - ANTHROPIC_MODEL          : メイン会話モデル（Sonnet）
# - ANTHROPIC_SMALL_FAST_MODEL: 裏方処理用の軽量モデル（Haiku）。タイトル生成・軽量分類などで
#                               Claude Code が別経路で呼ぶため、これもフル ID にしないと裏方が 403 になる。
WEBS_AI_DEFAULT_MODEL="global.anthropic.claude-sonnet-4-6"
WEBS_AI_DEFAULT_SMALL_FAST_MODEL="global.anthropic.claude-haiku-4-5-20251001-v1:0"

# 接続先 URL / モデルの決め方（優先順位）:
#   1. メンターから配られて保存済みの値（$WEBS_AI_CRED_FILE の WEBS_AI_GATEWAY_URL /
#      WEBS_AI_MODEL_ID / WEBS_AI_SMALL_FAST_MODEL_ID）
#   2. 上が無ければ、このスクリプトのハードコード既定値（WEBS_AI_DEFAULT_*）※あくまでフォールバック
# 以前は「常にハードコード値で固定」していた（同じシェルに残った旧 URL が原因で 403 に詰まる事故の
# 再発防止のため）。今は URL/モデルもメンター配布で受け取れるようにしたので、「環境に残った古い値」
# ではなく「保存済みの値」を source のたびに読み直して優先する方式にする。
# これにより、API 再作成で URL やモデルが変わっても、スクリプトを配り直さずメンターが新値を伝えるだけで直せる。
#
# モデルは 2 種類をメンター配布・入力で受け取る（固定しない）:
#   - Claude Code 用（"sonnet" を含むフル ID）→ ANTHROPIC_MODEL（WEBS_AI_MODEL）
#   - サービス(API)/裏方用（"haiku" を含むフル ID）→ ANTHROPIC_SMALL_FAST_MODEL（Claude Code の裏方）
#     ＋ AI_GATEWAY_MODEL（Sinatra 等のサービスが読む）。1 つの haiku 値で両方を賄う。
#
# まず working 変数を既定値で初期化しておく（後段の保存値/入力があれば上書きする）。
WEBS_AI_REGION="$WEBS_AI_DEFAULT_REGION"
WEBS_AI_GATEWAY_BASE_URL="$WEBS_AI_DEFAULT_GATEWAY_BASE_URL"
WEBS_AI_MODEL="$WEBS_AI_DEFAULT_MODEL"
WEBS_AI_SMALL_FAST_MODEL="$WEBS_AI_DEFAULT_SMALL_FAST_MODEL"
export AWS_REGION="$WEBS_AI_REGION"
# 既定値をひとまず export（保存値/入力があれば後段で上書き。古い環境変数の残骸を潰す意味もある）。
export ANTHROPIC_BASE_URL="$WEBS_AI_GATEWAY_BASE_URL"
export ANTHROPIC_MODEL="$WEBS_AI_MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
# サービス(API)が読むモデル名。裏方 Haiku と同じ値を使う（サービスは AI_GATEWAY_MODEL を参照）。
export AI_GATEWAY_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
: "${WEBS_AI_CRED_FILE:=$HOME/.lit-webs-ai/credentials}"
: "${WEBS_AI_QUIZ_PASS_FILE:=$HOME/.lit-webs-ai/quiz-passed}"
: "${WEBS_AI_MENTOR_SKIP_PASSWORD:=litbilson}"
# ---------- スクリプト自身のパスを bash/zsh 両対応で解決 ----------
# bash: BASH_SOURCE[0] が source 元ファイルのパス
# zsh:  prompt expansion (%x) を eval 経由で評価する
#       （zsh 専用構文を直書きすると bash が parse error を起こすため）
if [ -n "${BASH_VERSION:-}" ]; then
  WEBS_AI_SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  # eval で zsh 構文を遅延評価
  eval 'WEBS_AI_SCRIPT_PATH="${(%):-%x}"'
else
  WEBS_AI_SCRIPT_PATH="$0"
fi
: "${WEBS_AI_TEMPLATE_DIR:=$(cd "$(dirname "$WEBS_AI_SCRIPT_PATH")/.." && pwd)}"

# ---------- カラー（先に定義）：早期リターン分岐内でも色を使うため ----------
ESC_EARLY=$'\033'
RESET_EARLY="${ESC_EARLY}[0m"
BOLD_EARLY="${ESC_EARLY}[1m"
DIM_EARLY="${ESC_EARLY}[2m"
GREEN_EARLY="${ESC_EARLY}[32m"
YELLOW_EARLY="${ESC_EARLY}[33m"
RED_EARLY="${ESC_EARLY}[31m"
ORANGE_EARLY="${ESC_EARLY}[38;5;208m"
PINK_EARLY="${ESC_EARLY}[38;5;205m"
WHITE_EARLY="${ESC_EARLY}[37m"

# ---------- bash / sh で直接実行されてないかチェック ----------
# このスクリプトは環境変数 (ANTHROPIC_AUTH_TOKEN など) を呼び出し元のシェルに
# export する必要がある。`bash xxx.sh` だと子プロセスで動くため反映されない。
# 必ず `source` で実行してもらう。
# bash と zsh の両方に対応するため両方の方法でチェック。
_webs_is_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  # zsh では $ZSH_EVAL_CONTEXT に "file" が含まれていれば source されている
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file*) _webs_is_sourced=1 ;;
  esac
elif [ -n "${BASH_VERSION:-}" ]; then
  # bash では BASH_SOURCE[0] と $0 が違えば source されている
  if [ "${BASH_SOURCE[0]:-}" != "${0}" ]; then
    _webs_is_sourced=1
  fi
fi

if [ "$_webs_is_sourced" = "0" ]; then
  echo
  printf "%b\n" "  ${RED_EARLY}${BOLD_EARLY}⚠️  ちょっと待って！起動の仕方が違うよ${RESET_EARLY}"
  echo
  printf "%b\n" "  ${WHITE_EARLY}このスクリプトは ${BOLD_EARLY}source${RESET_EARLY}${WHITE_EARLY} で起動するんだ。${RESET_EARLY}"
  printf "%b\n" "  ${WHITE_EARLY}下のコマンドをそのままコピペしてね👇${RESET_EARLY}"
  echo
  printf "%b\n" "    ${PINK_EARLY}${BOLD_EARLY}source ${0:-scripts/lit-webs-ai.sh}${RESET_EARLY}"
  echo
  printf "%b\n" "  ${DIM_EARLY}（source は「ソース」って読むよ。おまじないみたいなものだよ✨）${RESET_EARLY}"
  echo
  exit 1
fi
unset _webs_is_sourced

# ---------- サイレントリフレッシュ（保存済みアクセスキーの再エクスポート）----------
# WEBS_AI_REFRESH=1 で呼ばれた場合は、ユーザーに何も聞かずに、保存済みの
# アクセスキーを環境変数へ再エクスポートするだけ。アクセスキーは失効しない限り
# 期限切れにならないため、トークン更新のような処理は不要（cron / PROMPT_COMMAND
# から呼ばれても無音で完了する）。保存されたアクセスキーがない場合は通常フローに進む。
SILENT_REFRESH=0
if [ "${WEBS_AI_REFRESH:-0}" = "1" ]; then
  SILENT_REFRESH=1
fi

# ---------- 無人サイレントリフレッシュ（バナー・メニューより前に最優先で処理）----------
# WEBS_AI_REFRESH=1 で呼ばれたら、バナー／開始メニュー／クイズを一切出さずに、保存済みアクセスキーを
# 環境変数へ再エクスポートするだけで即 return する。これにより、再起動後に ~/.bashrc / ~/.zshrc から
# 無人で source されても、入力待ち（read）でブロックせず、ターミナルを開いた瞬間に Claude が使える。
# 保存キーが無い場合も無人実行をブロックしないよう静かに return する（初回ログインは WEBS_AI_REFRESH を
# 付けずに対話で行う想定。メンター同席で 1 回だけ）。
if [ "$SILENT_REFRESH" = "1" ]; then
  _webs_refresh_key=""
  if [ -f "$WEBS_AI_CRED_FILE" ]; then
    # shellcheck disable=SC1090
    . "$WEBS_AI_CRED_FILE"
    _webs_refresh_key="${WEBS_AI_ACCESS_KEY:-}"
    # メンターから配られて保存済みの URL / モデルがあれば、それを優先で使う（無ければ既定値のまま）。
    [ -n "${WEBS_AI_GATEWAY_URL:-}" ] && WEBS_AI_GATEWAY_BASE_URL="$WEBS_AI_GATEWAY_URL"
    [ -n "${WEBS_AI_MODEL_ID:-}" ] && WEBS_AI_MODEL="$WEBS_AI_MODEL_ID"
    [ -n "${WEBS_AI_SMALL_FAST_MODEL_ID:-}" ] && WEBS_AI_SMALL_FAST_MODEL="$WEBS_AI_SMALL_FAST_MODEL_ID"
  fi
  if [ -n "$_webs_refresh_key" ]; then
    # 保存済みの URL / モデル（無ければ既定値）とキーをまとめて再エクスポート。
    export ANTHROPIC_BASE_URL="$WEBS_AI_GATEWAY_BASE_URL"
    export ANTHROPIC_AUTH_TOKEN="$_webs_refresh_key"
    export ANTHROPIC_MODEL="$WEBS_AI_MODEL"
    export ANTHROPIC_SMALL_FAST_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
    export AI_GATEWAY_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
    export AWS_REGION="$WEBS_AI_REGION"
    export WEBS_AI_INITIALIZED=1
  fi
  unset _webs_refresh_key
  return 0 2>/dev/null || exit 0
fi

# ---------- 既にこのセッションでセットアップ済みなら、ログアウト確認だけする ----------
# ただし SILENT_REFRESH=1 のときはこのブロック自体をスキップして、下の通常フロー
# で保存済みアクセスキーの再エクスポートが走る
if [ "${WEBS_AI_INITIALIZED:-0}" = "1" ] && [ "$SILENT_REFRESH" = "0" ]; then
  echo
  printf "%b\n" "  ${PINK_EARLY}${BOLD_EARLY}🔐 もうログイン済みだよ！${RESET_EARLY}"
  echo
  printf "%b\n" "  ${WHITE_EARLY}どうする？番号で選んでね${RESET_EARLY}"
  echo
  printf "%b\n" "    ${ORANGE_EARLY}1)${RESET_EARLY} このまま続ける ${DIM_EARLY}(何もしないでログイン状態を維持)${RESET_EARLY}"
  printf "%b\n" "    ${ORANGE_EARLY}2)${RESET_EARLY} ログアウトする ${DIM_EARLY}(別のアカウントに切り替えたいときなど)${RESET_EARLY}"
  echo
  printf "%b" "  ${PINK_EARLY}${BOLD_EARLY}▶${RESET_EARLY} ${ORANGE_EARLY}番号を入力して Enter:${RESET_EARLY} "
  read -r RELOGIN_CHOICE
  case "$RELOGIN_CHOICE" in
    2)
      # 本体に統合した webs-logout 関数を直接呼ぶ（別ファイル不要）
      webs-logout

      # ログアウト後に再ログインするか聞く
      echo
      printf "%b\n" "  ${WHITE_EARLY}そのまま別のアカウントでログインする？${RESET_EARLY}"
      echo
      printf "%b\n" "    ${ORANGE_EARLY}1)${RESET_EARLY} うん、続けてログインする"
      printf "%b\n" "    ${ORANGE_EARLY}2)${RESET_EARLY} ううん、また今度"
      echo
      printf "%b" "  ${PINK_EARLY}${BOLD_EARLY}▶${RESET_EARLY} ${ORANGE_EARLY}番号を入力して Enter:${RESET_EARLY} "
      read -r RELOGIN_NEXT
      case "$RELOGIN_NEXT" in
        1|"")
          # ログイン処理に進むため、return せずに下に流す（WEBS_AI_INITIALIZED は logout 内で unset 済み）
          echo
          printf "%b\n" "  ${GREEN_EARLY}OK！このまま新しいアカウントでログインしよう✨${RESET_EARLY}"
          echo
          # ここでは return せず、スクリプト本体（バナー以降）に処理を流す
          ;;
        *)
          printf "%b\n" "  ${DIM_EARLY}またね〜！次にログインしたいときは、もう一回このスクリプトを source してね${RESET_EARLY}"
          echo
          return 0 2>/dev/null
          ;;
      esac
      ;;
    *)
      printf "%b\n" "  ${GREEN_EARLY}OK！このまま続けるね 👍${RESET_EARLY}"
      echo
      return 0 2>/dev/null || exit 0
      ;;
  esac
fi

# ---------- ページめくり用ヘルパー ----------
press_next() {
  printf "\n%b" "  ${DIM}── Enter キーで次へ ──${RESET}"
  read -r _
}

print_page_header() {
  local current=$1
  local total=$2
  local title=$3
  clear
  print_banner
  printf "%b\n" "  ${DIM}page ${current} / ${total}${RESET}    ${PINK}${BOLD}${title}${RESET}"
  echo
}

print_banner

# ---------- 開始メニュー ----------
QUIZ_PASSED=0
[ -f "$WEBS_AI_QUIZ_PASS_FILE" ] && QUIZ_PASSED=1

if [ "$QUIZ_PASSED" = "1" ]; then
  # 2 回目以降のセットアップ（クイズ合格済み）
  printf "%b\n" "  ${WHITE}おかえり〜！${RESET} ${PINK}✨${RESET}"
  echo
  printf "%b\n" "  ${PINK}${BOLD}💡 前回 AI のクイズに合格してるね！${RESET}"
  printf "%b\n" "  ${WHITE}でも環境が変わったから、もう一回セットアップが必要なんだ。${RESET}"
  echo
  printf "%b\n" "  ${WHITE}${BOLD}メンターさんを呼んで『スキップしたい』って伝えてね${RESET}"
  printf "%b\n" "  ${WHITE}パスワードを入れてもらうと、そのままログインに進めるよ${RESET}"
  echo
  printf "%b\n" "  ${BOLD}どうする？番号で選んでね${RESET}"
  echo
  printf "%b\n" "    ${ORANGE}1)${RESET} もう一回 AI の説明から受ける ${DIM}(自分でやり直したい方はこっち)${RESET}"
  printf "%b\n" "    ${ORANGE}2)${RESET} スキップする ${DIM}(メンターさんのパスワードが必要)${RESET}"
else
  # 初回
  printf "%b\n" "  ${WHITE}やっほー！ようこそ Life is Tech! へ！${RESET} ${PINK}🥳${RESET}"
  printf "%b\n" "  ${WHITE}今日からみんなでめっちゃカッコいい Web サービス作ってこ〜！${RESET}"
  echo
  printf "%b\n" "  ${BOLD}まずは AI のことを知るところから！${RESET}"
  echo
  printf "%b\n" "    ${ORANGE}1)${RESET} スタート ${DIM}(初めての方はこっち。AI の説明を読んで、クイズを受けるよ)${RESET}"
  printf "%b\n" "    ${ORANGE}2)${RESET} スキップ ${DIM}(2 回目以降、合格済みの方はこっち)${RESET}"
fi

echo
printf "%b" "  ${PINK}${BOLD}▶${RESET} ${ORANGE}番号を入力して Enter:${RESET} "
read -r CHOICE

SKIP_LESSON=0
case "$CHOICE" in
  2)
    echo
    printf "%b\n" "  ${DIM}メンターさんを呼んで、パスワードを入れてもらってね${RESET}"
    printf "%b\n" "  ${DIM}（セキュリティのために、入力した文字は画面に表示されません）${RESET}"
    printf "%b" "  ${ORANGE}メンターパスワード:${RESET} "
    # -s で入力をエコーバックしない（パスワード保護）
    read -r -s MENTOR_INPUT
    echo
    if [ "$MENTOR_INPUT" = "$WEBS_AI_MENTOR_SKIP_PASSWORD" ]; then
      SKIP_LESSON=1
      ok "メンター確認 OK！ログインに進むね"
    else
      warn "パスワードが違うみたい...説明から一緒に始めよう！"
    fi
    ;;
  1|"")
    # スタート（既定）
    :
    ;;
  *)
    echo
    warn "番号がよくわからなかったから、説明から始めるね！"
    ;;
esac

# ---------- 説明ページ（6 ページ + クイズ） ----------
if [ "$SKIP_LESSON" = "0" ]; then
  TOTAL_PAGES=6

  # ── ページ 0：予告 ──
  clear
  print_banner
  printf "%b\n" "  ${PINK}${BOLD}📖 これから AI のことを勉強するよ！${RESET}"
  echo
  cat <<EOF
  これから ${TOTAL_PAGES} ページの説明を読んでもらうね。
  時間にして 3〜5 分くらいかな。

  ${YELLOW}${BOLD}⚠️  最後にクイズが ${TOTAL_PAGES} 問あるから、ちゃんと読んでね！${RESET}
  ${YELLOW}全問正解しないと先に進めないから、しっかり覚えていこう。${RESET}

  ${DIM}（合格したら、次回から自動でスキップされるよ）${RESET}
EOF
  press_next

  # ── ページ 1：Anthropic って？ ──
  print_page_header 1 $TOTAL_PAGES "Anthropic ってなに？"
  cat <<EOF
  みんな、これから AI を使って Web サービスを作るんだけど、
  そもそも AI って誰が作ってるか知ってる？

  今回みんなが使う AI は「${BOLD}Anthropic（アンソロピック）${RESET}」
  っていう会社が作ってるんだ。

  Anthropic はね、「${BOLD}AI を安全に作る${RESET}」ことをめっちゃ大事にしてる
  アメリカの会社だよ。元 OpenAI（ChatGPT 作ってる会社）の人たちが
  独立して作った、結構新しい会社なんだ。

  「みんなが安心して AI を使えるように」っていう想いで研究してて、
  そこで生まれたのが今日みんなが使う AI ── ${PINK}${BOLD}クロード${RESET} だよ✨
EOF
  press_next

  # ── ページ 2：クロードって何？ ──
  print_page_header 2 $TOTAL_PAGES "クロードってなに？"
  cat <<EOF
  クロード（Claude）は、Anthropic が作った ${BOLD}会話できる AI${RESET} だよ。
  ChatGPT みたいなものだと思ってくれて OK！

  クロードができること：

    ${GREEN}◆${RESET} 質問に答える（プログラミング、調べ物、相談）
    ${GREEN}◆${RESET} コードを書く（今日みんながやるやつ！）
    ${GREEN}◆${RESET} 文章を考える、要約する
    ${GREEN}◆${RESET} アイデアを一緒に考える

  でもね、クロードは ${BOLD}魔法じゃない${RESET}。
  「あれ作って！」って一言投げたら全部やってくれる、
  みたいなのとはちょっと違うんだ。

  使い方を知ってると、すごく頼れるパートナーになるよ💪
EOF
  press_next

  # ── ページ 3：AI との付き合い方 ──
  print_page_header 3 $TOTAL_PAGES "AI との付き合い方"
  cat <<EOF
  これ、${BOLD}今日いちばん大事${RESET} かもしれない。

  AI に「全部やって！」って丸投げするのは、実はもったいない使い方なんだ。
  なぜかっていうと、「${BOLD}何を作りたいか${RESET}」を決めるのは
  ${PINK}${BOLD}君自身${RESET} だから。

  AI はね、こんな感じで使うのがベスト：

    ${ORANGE}◆${RESET} 「何を作るか」は ${BOLD}自分で${RESET} 決める
    ${ORANGE}◆${RESET} 「どうやって作るか」を AI と ${BOLD}一緒に考える${RESET}
    ${ORANGE}◆${RESET} 困ったら AI に ${BOLD}聞いてみる${RESET}（恥ずかしくない！）
    ${ORANGE}◆${RESET} AI が出した答えを ${BOLD}自分で読んで理解する${RESET}

  つまり、AI は「${BOLD}一緒に考えてくれるパートナー${RESET}」。
  主役は君！自分で考えて、自分で作る体験を大切にしてね🎨
EOF
  press_next

  # ── ページ 4：安全に使うために ──
  print_page_header 4 $TOTAL_PAGES "安全に使うために"
  cat <<EOF
  AI とのやりとりはインターネット越しに行われるよ。
  だから、${BOLD}個人情報は教えない${RESET} ── これ絶対！

  AI に教えちゃダメなこと：

    ${RED}✗${RESET} ${BOLD}本名（フルネーム）${RESET} ── ニックネームで OK！
    ${RED}✗${RESET} ${BOLD}住所${RESET} や ${BOLD}電話番号${RESET}
    ${RED}✗${RESET} 学校名（細かい情報）
    ${RED}✗${RESET} パスワード、クレジットカード番号
    ${RED}✗${RESET} 友達の個人情報（自分の情報以上にダメ！）

  逆に、こういうのは全然 OK：

    ${GREEN}✓${RESET} 推しの名前、好きなアニメ／ゲーム
    ${GREEN}✓${RESET} 趣味、興味あること
    ${GREEN}✓${RESET} 作りたいサービスのアイデア

  あと、${BOLD}わからないことや困ったことはメンターさんに相談${RESET}！
  AI に何でも聞いていいけど、人に聞くのも大事だよ😊
EOF
  press_next

  # ── ページ 5：著作権 ──
  print_page_header 5 $TOTAL_PAGES "他人の作ったものは勝手に使わない（著作権／ちょさくけん）"
  cat <<EOF
  Web サービスを作ってると、こんな誘惑がよくあるよ：

    「推しの公式画像をサイトに貼っちゃおう！」
    「○○の歌詞をそのまま載せちゃえ！」
    「人気漫画のキャラを使ったゲーム作ろ！」

  でもね、これ全部 ${BOLD}ダメ${RESET} なんだ。

  世の中のあらゆる ${BOLD}画像・音楽・歌詞・イラスト・キャラ${RESET} には、
  作った人の「これは私の作品です」っていう ${PINK}${BOLD}著作権（ちょさくけん）${RESET} がある。
  勝手に使うと、たとえ趣味でも法律違反になっちゃう💦

  ${GREEN}OK な使い方：${RESET}
    ${GREEN}◆${RESET} 自分で描いた絵、自分で撮った写真
    ${GREEN}◆${RESET} 「フリー素材」って書いてあるもの（規約は読む！）
    ${GREEN}◆${RESET} 公式 YouTube の埋め込み（リンクで紹介する形）
    ${GREEN}◆${RESET} 自分の言葉で「○○について語る」テキスト

  ${RED}NG な使い方：${RESET}
    ${RED}✗${RESET} ネットから拾った画像をそのまま貼る
    ${RED}✗${RESET} 歌詞を全部コピペする
    ${RED}✗${RESET} 公式キャラのイラストを使う

  迷ったら ${BOLD}メンターさんに相談${RESET}！
  「これ使っていい？」って聞くのが一番安全だよ💪
EOF
  press_next

  # ── ページ 6：AI は完璧じゃない ──
  print_page_header 6 $TOTAL_PAGES "AI は完璧じゃない"
  cat <<EOF
  最後にこれだけ覚えといて：${BOLD}AI もたまに間違う${RESET}。

  AI はね、めっちゃ賢く見えるけど、実は：

    ${YELLOW}◆${RESET} 知らないことを ${BOLD}知ってるフリ${RESET} することがある
        （これを「${BOLD}ハルシネーション${RESET}」って言うよ）
    ${YELLOW}◆${RESET} 古い情報を答えちゃうことがある
    ${YELLOW}◆${RESET} 思い込みで間違ったコードを書くことがある

  だから、AI が言ったことを ${BOLD}全部信じない${RESET} のが大事。

  「${BOLD}本当かな？${RESET}」って一回考えるクセをつけてね。
  動かなかったら、メンターさんと一緒に見てみよう！
  間違いを見つけるのも、プログラマーの大事な力なんだ💪

  ${PINK}${BOLD}じゃあ最後にクイズで確認してみよう！${RESET}
EOF
  press_next

  # ---------- クイズ ----------
  clear
  print_banner
  printf "%b\n" "  ${PINK}${BOLD}🎯 クイズタイム（全 6 問）${RESET}"
  echo
  printf "%b\n" "  ${YELLOW}${BOLD}全問正解で合格！${RESET}"
  printf "%b\n" "  ${WHITE}安全に AI を使うために必要なルールだから、しっかりね${RESET}"
  echo
  printf "%b\n" "  ${DIM}間違えても何度でもチャレンジできるから、落ち着いて答えてね${RESET}"
  echo
  press_next

  # クイズ出題関数。
  # - 選択肢を毎回シャッフル（番号も振り直す）
  # - 回答後すぐに正誤を出さず、間違えたら解説を WRONG_REPORTS に蓄積
  # - 全問終わってから一気に「結果＋間違えた問題の解説」を表示する
  QUIZ_NUM=0
  WRONG_REPORTS=()

  ask_quiz() {
    local q="$1"; shift
    local correct_orig="$1"; shift   # 元の正解番号 (1〜4)
    local explanation="$1"; shift
    # 残り 4 つは選択肢（"    1) ..."形式）
    local raw_options=("$@")
    QUIZ_NUM=$((QUIZ_NUM + 1))

    # 各選択肢から本文だけ取り出す（"    1) xxx" → "xxx"）
    local bodies=()
    local i
    for i in "${!raw_options[@]}"; do
      # 先頭の空白＋数字＋")"＋空白を取り除く
      local body
      body="$(echo "${raw_options[$i]}" | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+//')"
      bodies+=("$body")
    done

    # 正解の本文（元の番号 - 1 がインデックス）
    local correct_body="${bodies[$((correct_orig - 1))]}"

    # シャッフル後の本文配列を作る
    local shuffled_bodies=()
    while IFS= read -r line; do
      shuffled_bodies+=("$line")
    done < <(printf '%s\n' "${bodies[@]}" | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -k1,1 | cut -f2-)

    # シャッフル後に正解が何番目になったか探す
    local correct_new=0
    local n
    for n in "${!shuffled_bodies[@]}"; do
      if [ "${shuffled_bodies[$n]}" = "$correct_body" ]; then
        correct_new=$((n + 1))
        break
      fi
    done

    # 表示
    echo
    printf "%b\n" "  ${BOLD}Q${QUIZ_NUM}. ${q}${RESET}"
    for n in "${!shuffled_bodies[@]}"; do
      printf "    %d) %s\n" "$((n + 1))" "${shuffled_bodies[$n]}"
    done
    echo
    printf "%b" "  ${ORANGE}答えの番号を入れてね:${RESET} "
    read -r ans

    if [ "$ans" = "$correct_new" ]; then
      # 正誤を表示せずに次の問題へ進む（最後にまとめて結果を出すため）
      printf "%b\n" "  ${DIM}── 次の問題へ ──${RESET}"
      return 0
    else
      printf "%b\n" "  ${DIM}── 次の問題へ ──${RESET}"
      # 間違えた問題は、シャッフル後の表示順を記録
      local options_str=""
      for n in "${!shuffled_bodies[@]}"; do
        options_str+="    $((n + 1))) ${shuffled_bodies[$n]}\n"
      done
      local report="  ${BOLD}Q${QUIZ_NUM}. ${q}${RESET}\n"
      report+="${options_str}"
      report+="  ${RED}あなたの答え：${ans:-（未入力）}${RESET}    ${GREEN}正解：${correct_new}${RESET}\n"
      report+="  ${DIM}${explanation}${RESET}\n"
      WRONG_REPORTS+=("$report")
      return 1
    fi
  }

  # クイズ問題定義（パイプ区切り：問題|正解|解説|選択肢1|選択肢2|選択肢3|選択肢4）
  # ─ 出題ごとに順番をシャッフルするので、配列内の順序は固定でも OK
  QUIZ_BANK=(
    "AI に教えていいのはどれ？|3|個人情報は絶対に AI に渡さない！推しの話なら OK 🌟|    1) 自分の本名と住所|    2) 友達の電話番号|    3) 推しのアニメの名前|    4) クレジットカード番号"
    "AI が言ったことが正しいかどうかは？|2|AI もたまに間違うから、自分で『本当かな？』って考えるクセをつけよう|    1) いつも 100% 正しい|    2) たまに間違うことがあるから自分でも考える|    3) 全部嘘なので絶対に信じない|    4) コードは正しいけど文章は嘘"
    "AI と一緒に Web サービスを作るとき、いちばん大事なのは？|4|主役は君！AI はパートナーだよ💪|    1) AI に全部丸投げしてラクする|    2) AI の言うとおりにそのまま作る|    3) AI に頼らず自分だけで全部作る|    4) 自分で『何を作るか』考えて、AI と一緒に進める"
    "今日みんなが使う AI 「クロード」を作ってるのはどこ？|3|Anthropic（アンソロピック）。安全な AI を作ってるアメリカの会社だよ|    1) Google|    2) OpenAI（ChatGPT 作ってる会社）|    3) Anthropic（アンソロピック）|    4) Apple"
    "AI に質問するとき、自分の名前はどう伝えるのがいい？|2|ニックネームでね！本名はインターネットでは教えないのが鉄則|    1) 本名フルネームを伝える|    2) ニックネームで伝える|    3) 学校の名前と一緒に伝える|    4) 住んでる住所と一緒に伝える"
    "推しのアイドルのファンサイトを作るとき、画像をどう使うのが正解？|4|公式画像や他人の写真を勝手に貼るのは著作権違反！リンクで紹介するか、自分で描こう|    1) Google 画像検索で見つけた公式写真を保存して貼る|    2) 推しが映ってるファンの SNS 写真を勝手に拝借|    3) 公式の歌詞をそのまま全部コピペする|    4) 公式 YouTube 動画を埋め込みリンクで紹介する"
  )

  attempt=0
  while true; do
    attempt=$((attempt + 1))
    score=0
    QUIZ_NUM=0
    WRONG_REPORTS=()

    # 問題の順番をシャッフル（毎回違う順序で出題）
    shuffled_quiz=()
    while IFS= read -r line; do
      shuffled_quiz+=("$line")
    done < <(printf '%s\n' "${QUIZ_BANK[@]}" | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -k1,1 | cut -f2-)

    for entry in "${shuffled_quiz[@]}"; do
      IFS='|' read -r q correct explanation opt1 opt2 opt3 opt4 <<< "$entry"
      ask_quiz "$q" "$correct" "$explanation" "$opt1" "$opt2" "$opt3" "$opt4" && score=$((score + 1))
    done

    echo
    echo
    printf "%b\n" "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    printf "%b\n" "  ${BOLD}結果：${score} / 6 問正解${RESET}"
    printf "%b\n" "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo

    if [ "$score" -eq 6 ]; then
      mkdir -p "$(dirname "$WEBS_AI_QUIZ_PASS_FILE")"
      date > "$WEBS_AI_QUIZ_PASS_FILE"
      clear
      print_banner

      # 合格バナー
      printf "%b\n" "${YELLOW}${BOLD}     ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★${RESET}"
      printf "%b\n" "${PINK}${BOLD}              🎉  ALL CLEAR!  🎉${RESET}"
      printf "%b\n" "${YELLOW}${BOLD}     ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★  ☆  ★${RESET}"
      echo

      # クロード使いこなし認定証カード
      local today
      today="$(date +'%Y-%m-%d')"

      printf "%b\n" "  ${PURPLE}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}                                                            ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}      ${PINK}${BOLD}クロード使いこなし認定証${RESET}                              ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}      ${DIM}── Claude Co-Creator License ──${RESET}                       ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}                                                            ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}   この認定証を持つ人は、AI のことをちゃんと理解して、       ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}   ${BOLD}クロードと一緒に Web サービスを作る権利${RESET} を得ました。  ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}                                                            ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}   発行日： ${WHITE}${today}${RESET}                                ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}   発行元： ${WHITE}Life is Tech! WebS${RESET}                            ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}║${RESET}                                                            ${PURPLE}${BOLD}║${RESET}"
      printf "%b\n" "  ${PURPLE}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
      echo
      printf "%b\n" "  ${GREEN}${BOLD}✨ おめでとう！${RESET} ${WHITE}AI と一緒にものづくり、楽しんでいこう！${RESET}"
      echo
      press_next
      break
    else
      # 間違えた問題の解説を一気に表示
      printf "%b\n" "  ${YELLOW}${BOLD}間違えた問題の解説を見てみよう👇${RESET}"
      echo
      for report in "${WRONG_REPORTS[@]}"; do
        printf "%b\n" "$report"
      done
      printf "%b\n" "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
      echo

      if [ "$attempt" -ge 2 ]; then
        printf "%b\n" "  ${YELLOW}うーん、もう少しだね...！${RESET}"
        echo
        printf "%b\n" "  ${ORANGE}${BOLD}メンターさんを呼んでみよう 🙋${RESET}"
        printf "%b\n" "  ${WHITE}『クイズで詰まっちゃった〜』って言えば、一緒に見てくれるよ！${RESET}"
        printf "%b\n" "  ${DIM}（安全のために全問正解が必要なんだ。一緒に確認してもらおう）${RESET}"
      else
        printf "%b\n" "  ${YELLOW}惜しい！合格は ${BOLD}全問正解${RESET}${YELLOW} だよ。もう一回チャレンジしてみよう💪${RESET}"
      fi
      echo
      press_next
    fi
  done

  clear
  print_banner
fi

# ---------- ここからが本来のセットアップ ----------
printf "%b\n" "  ${WHITE}じゃあ AI を起動する準備をしてくね...ちょっとだけ待ってて！${RESET}"
echo

# ---------- 前提コマンドのチェック ----------
# アクセスキー方式では aws / jq は不要（キーをそのまま使うだけ）。特別な前提コマンドは
# ないため、ここでは何もしない。
step "AI を動かす準備をはじめるよ..."
ok "OK！特別な道具は必要ないよ"

# ---------- 設定値が埋まっているか先に確認（保存前にチェック）----------
echo
step "AI のお家のアドレスを確認..."
if [ "$WEBS_AI_GATEWAY_BASE_URL" = "__SET_ME__" ]; then
  fail "あれれ、設定が足りないみたい！メンターさんに見てもらってね 💦"
  return 1 2>/dev/null || exit 1
fi
ok "アドレス確認 OK！"

# ---------- 認証（保存済みアクセスキーがあれば再利用、なければ入力）----------
# 注: SILENT_REFRESH=1 の経路は冒頭の「無人サイレントリフレッシュ」ブロックで既に return 済みのため、
# ここから下は対話モード（SILENT_REFRESH=0）のみが到達する。
echo
step "Life is Tech! の AI 接続情報でログインするよ"

ACCESS_KEY=""

# 保存済みの接続情報（キー / URL / モデル）があれば読み込む
if [ -f "$WEBS_AI_CRED_FILE" ]; then
  # shellcheck disable=SC1090
  source "$WEBS_AI_CRED_FILE"
  ACCESS_KEY="${WEBS_AI_ACCESS_KEY:-}"
  # メンターから配られて保存済みの URL / モデルがあれば working 変数へ反映（無ければ既定値のまま）。
  [ -n "${WEBS_AI_GATEWAY_URL:-}" ] && WEBS_AI_GATEWAY_BASE_URL="$WEBS_AI_GATEWAY_URL"
  [ -n "${WEBS_AI_MODEL_ID:-}" ] && WEBS_AI_MODEL="$WEBS_AI_MODEL_ID"
  [ -n "${WEBS_AI_SMALL_FAST_MODEL_ID:-}" ] && WEBS_AI_SMALL_FAST_MODEL="$WEBS_AI_SMALL_FAST_MODEL_ID"
fi

# ---------- 次回から自動で繋がるよう rc へ自動ロード行を登録（冪等）----------
# 生徒が毎回 source しなくて済むよう、ログイン成功時に一度だけ ~/.bashrc（zsh なら ~/.zshrc）へ
# 「WEBS_AI_REFRESH=1 source <このスクリプトの絶対パス>」を追記する。これにより、以降は
# ターミナルを開くたびにシェルが無人で自動リフレッシュし、生徒は何も打たずに Claude が使える。
# 既に登録済み（マーカー検出）なら何もしない。書き込みに失敗してもログインは止めない。
webs_install_autoload() {
  # 追記先 rc を、いま動いているシェル種別で決める（生徒が普段使う対話シェルと同じ）。
  if [ -n "${ZSH_VERSION:-}" ]; then
    _webs_rc="$HOME/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    _webs_rc="$HOME/.bashrc"
  else
    _webs_rc="$HOME/.profile"
  fi

  # このスクリプトの絶対パスを解決（cwd に依存せず source できるようにする）。
  _webs_abs="$(cd "$(dirname "$WEBS_AI_SCRIPT_PATH")" 2>/dev/null && pwd)/$(basename "$WEBS_AI_SCRIPT_PATH")"
  if [ ! -f "$_webs_abs" ]; then
    # 絶対パスが解決できないときは自動登録を見送る（手動 source は引き続き可能）。
    unset _webs_rc _webs_abs
    return 0
  fi

  _webs_marker="# >>> lifeistech-webs-ai auto-load >>>"

  # 既に登録済みなら何もしない（冪等）。
  if [ -f "$_webs_rc" ] && grep -qF "$_webs_marker" "$_webs_rc" 2>/dev/null; then
    unset _webs_rc _webs_abs _webs_marker
    return 0
  fi

  # マーカーで囲んで 1 ブロック追記（ヒアドキュメントは使わず printf で安全に書く）。
  {
    printf '\n%s\n' "$_webs_marker"
    printf '%s\n' "# ターミナルを開くたびに WebS AI 接続情報を自動で読み込む（毎回の source 不要）。"
    printf '%s\n' "WEBS_AI_REFRESH=1 source \"$_webs_abs\""
    printf '%s\n' "# <<< lifeistech-webs-ai auto-load <<<"
  } >> "$_webs_rc" 2>/dev/null &&
    ok "次回からはターミナルを開くだけで自動で繋がるよ ✨（$_webs_rc に登録したよ）"

  unset _webs_rc _webs_abs _webs_marker
}

# ---------- Claude Code の初回対話画面を先回りでスキップさせる ----------
# 中高生メンバーが `claude` を初めて起動すると、次の 3 つの対話画面が順に出てきて、
# 矢印キーやパスワード的な確認を求められる（メンバーには難しく、詰まりやすい）:
#   1. テーマ選択（Choose the text style ...）
#   2. フォルダ信頼（このフォルダのファイルを使ってもいい？）
#   3. Bypass Permissions mode（Yes, I accept … 毎回の許可確認を省く危険モード）
# これらは Claude Code の設定ファイルに保存される値で決まるので、セットアップ時に
# あらかじめ書き込んでおけば、メンバーは最初から何も聞かれずに Claude が使える。
#
# 書き込み先:
#   ~/.claude/settings.json : theme / permissions.defaultMode=bypassPermissions /
#                             skipDangerousModePermissionPrompt=true
#   ~/.claude.json          : hasCompletedOnboarding=true（＋作業フォルダの信頼フラグ）
#
# ⚠ 重要（メンター向けメモ）:
#   defaultMode=bypassPermissions は「ファイル書き込みやコマンド実行を毎回確認せず実行する」
#   モード（本家フラグ名は --dangerously-skip-permissions）。キャンプの隔離環境で、いちいち
#   許可を押さずに進めるための意図的な設定。手元の私物 PC 等で使い回さないこと。
#
# 既存の設定を壊さないよう、node で「読み込み→必要キーだけ追加→書き戻し」する
# （OAuth セッションや MCP 設定などは保持）。node が無い環境では、ファイルが未作成のときだけ
# 最小 JSON を新規作成する（既存ファイルには触らない）。
webs_setup_claude_defaults() {
  # 使うテーマ（メンター側で WEBS_CC_THEME=light 等に上書き可）。既定は dark。
  : "${WEBS_CC_THEME:=dark}"
  export WEBS_CC_THEME
  # いま居るフォルダを「信頼済み」にしておく（メンバーがここで claude を起動する想定）。
  # bypass モードは新規フォルダでも信頼確認を省くが、念のため現在地も登録しておく。
  export WEBS_CC_TRUST_DIR="$PWD"

  _cc_settings="$HOME/.claude/settings.json"
  _cc_json="$HOME/.claude.json"

  if command -v node >/dev/null 2>&1; then
    # --- node があれば：既存を壊さずマージ（推奨経路）---
    _cc_helper="$HOME/.lit-webs-ai/claude-defaults.js"
    mkdir -p "$(dirname "$_cc_helper")"
    # JS 本体を書き出す（シングルクオートは一切使わず、シェルの継続プロンプト固着を回避）。
    printf '%s\n' 'const fs = require("fs");
const os = require("os");
const path = require("path");
function load(p) { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { return {}; } }
function save(p, o) { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, JSON.stringify(o, null, 2) + "\n"); }
const home = os.homedir();
const theme = process.env.WEBS_CC_THEME || "dark";
const sp = path.join(home, ".claude", "settings.json");
const s = load(sp);
if (!s.theme) s.theme = theme;
if (!s.permissions) s.permissions = {};
if (!s.permissions.defaultMode) s.permissions.defaultMode = "bypassPermissions";
s.skipDangerousModePermissionPrompt = true;
save(sp, s);
const cp = path.join(home, ".claude.json");
const c = load(cp);
c.hasCompletedOnboarding = true;
if (!c.theme) c.theme = theme;
const td = process.env.WEBS_CC_TRUST_DIR;
if (td) {
  if (!c.projects) c.projects = {};
  if (!c.projects[td]) c.projects[td] = {};
  c.projects[td].hasTrustDialogAccepted = true;
}
save(cp, c);
console.log("ok");' > "$_cc_helper"

    if node "$_cc_helper" >/dev/null 2>&1; then
      ok "Claude の初回画面（テーマ / フォルダ信頼 / 権限）を自動で済ませたよ ✨"
    else
      warn "Claude の初回設定の自動化に失敗したよ（初回起動時に画面が出るかも）"
    fi
    # 使い捨てヘルパーは実行後すぐ削除（作業用ファイルを残さない）。
    rm -f "$_cc_helper"
    unset _cc_helper
  else
    # --- node が無い環境：ファイルが未作成のときだけ最小 JSON を新規作成 ---
    if [ ! -f "$_cc_settings" ]; then
      mkdir -p "$(dirname "$_cc_settings")"
      printf '%s\n' "{
  \"theme\": \"$WEBS_CC_THEME\",
  \"permissions\": { \"defaultMode\": \"bypassPermissions\" },
  \"skipDangerousModePermissionPrompt\": true
}" > "$_cc_settings"
    fi
    if [ ! -f "$_cc_json" ]; then
      printf '%s\n' "{
  \"hasCompletedOnboarding\": true,
  \"theme\": \"$WEBS_CC_THEME\"
}" > "$_cc_json"
    fi
    ok "Claude の初回画面をスキップする設定を書いたよ ✨"
    dim "（既に設定ファイルがある場合はそのまま残してるよ）"
  fi

  unset _cc_settings _cc_json
}

# ---------- サービス用の gem を用意する（bundle install）----------
# このスクリプトはメンバーのプロジェクト内（例: <project>/member-scripts/lit-webs-ai.sh）に置かれる想定。
# その 1 つ上（＝プロジェクト直下 = $WEBS_AI_TEMPLATE_DIR）に Gemfile があれば bundle install を回して、
# メンバーが手で `bundle install` しなくても Sinatra / faraday / dotenv 等がそろうようにする。
#
# ベストエフォート方針:
#   - Gemfile が無い / bundle コマンドが無い → 何もせず静かにスキップ（手動 install は引き続き可能）。
#   - install に失敗しても（Ruby バージョン不一致・ネイティブ拡張のビルド不可など）AI セットアップは
#     止めない。ログ（$HOME/.lit-webs-ai/bundle-install.log）に残し、末尾だけ表示して手動を促す。
webs_bundle_install() {
  # Gemfile を探す（プロジェクト直下を最優先、無ければカレントディレクトリ）。
  _gemfile_dir=""
  if [ -f "$WEBS_AI_TEMPLATE_DIR/Gemfile" ]; then
    _gemfile_dir="$WEBS_AI_TEMPLATE_DIR"
  elif [ -f "$PWD/Gemfile" ]; then
    _gemfile_dir="$PWD"
  fi

  if [ -z "$_gemfile_dir" ]; then
    dim "Gemfile が見つからないので gem の準備はスキップ（あとで bundle install してね）"
    unset _gemfile_dir
    return 0
  fi

  if ! command -v bundle >/dev/null 2>&1; then
    warn "bundle コマンドが無いので gem の準備はスキップ（あとで手動で bundle install してね）"
    unset _gemfile_dir
    return 0
  fi

  step "サービス用の gem を準備中（bundle install）...ちょっとかかるよ"
  _bundle_log="$HOME/.lit-webs-ai/bundle-install.log"
  mkdir -p "$(dirname "$_bundle_log")"
  # サブシェルで cd するので、呼び出し元のカレントディレクトリは変わらない。
  if ( cd "$_gemfile_dir" && bundle install ) > "$_bundle_log" 2>&1; then
    ok "gem の準備ができたよ ✨（$_gemfile_dir）"
  else
    warn "gem の自動インストールがうまくいかなかったみたい"
    dim "あとで手動で試してね: cd \"$_gemfile_dir\" && bundle install"
    dim "くわしいログ: $_bundle_log"
    # ログの末尾だけそっと表示（原因のヒント）。
    tail -n 6 "$_bundle_log" 2>/dev/null | while IFS= read -r _bl; do
      dim "  $_bl"
    done
  fi
  unset _gemfile_dir _bundle_log _bl
}

# ---------- メンター配布の 4 点セット（URL / キー / Claude Code モデル / API モデル）を 1 つずつ入力 ----------
# メンターから配られる 4 つの値を、順番に「メンターさんに聞いてね」の案内つきで入力させる。
#   ① AI_GATEWAY_URL         → ANTHROPIC_BASE_URL   （接続先。必須。https:// 始まり）
#   ② AI_GATEWAY_KEY         → ANTHROPIC_AUTH_TOKEN （アクセスキー。必須。sk-aipf- 始まり）
#   ③ Claude Code モデル名   → ANTHROPIC_MODEL      （必須。"sonnet" を含むこと＝取り違え防止）
#   ④ API(サービス) モデル名 → ANTHROPIC_SMALL_FAST_MODEL ＋ AI_GATEWAY_MODEL（必須。"haiku" を含むこと）
# ③④ とも値は固定しない（メンター配布値）。含有チェックは「sonnet を API 側に、haiku を Claude Code 側に」
# 貼り違える事故を防ぐための軽いバリデーション。入力後、4 点セットを $WEBS_AI_CRED_FILE に保存する。
# working 変数（WEBS_AI_GATEWAY_BASE_URL / ACCESS_KEY / WEBS_AI_MODEL / WEBS_AI_SMALL_FAST_MODEL）を書き換える。
webs_prompt_gateway_config() {
  echo
  printf "%b\n" "  ${PINK}${BOLD}🔑 メンターさんから「AI の接続情報」を 4 つもらってね${RESET}"
  printf "%b\n" "  ${WHITE}『AI の接続情報ちょうだい』ってメンターさんに伝えると教えてくれるよ${RESET}"
  printf "%b\n" "  ${DIM}（① 接続先URL ② アクセスキー ③ Claude Codeモデル名 ④ APIモデル名 の 4 つ。ひとつずつ入れていこう）${RESET}"

  # --- ① 接続先URL（AI_GATEWAY_URL）※必須 ---
  WEBS_AI_GATEWAY_BASE_URL=""
  url_attempt=0
  while [ -z "$WEBS_AI_GATEWAY_BASE_URL" ]; do
    url_attempt=$((url_attempt + 1))
    echo
    printf "%b\n" "  ${ORANGE}${BOLD}① 接続先URL（AI_GATEWAY_URL）${RESET}"
    printf "%b\n" "  ${DIM}メンターさんに『接続先URLは？』って聞いて、そのまま貼り付けてね${RESET}"
    printf "%b\n" "  ${DIM}（「https://」で始まる URL だよ。貼り付けたら Enter）${RESET}"
    printf "%b" "  ${ORANGE}接続先URL:${RESET} "
    read -r _in_url
    _in_url="$(printf '%s' "$_in_url" | tr -d '[:space:]')"
    case "$_in_url" in
      https://*)
        WEBS_AI_GATEWAY_BASE_URL="$_in_url"
        ok "接続先URLを設定したよ"
        ;;
      "")
        fail "接続先URLが入力されなかったよ 💦"
        WEBS_AI_GATEWAY_BASE_URL=""
        ;;
      *)
        warn "URL は https:// で始まるはずだよ"
        printf "%b\n" "  ${DIM}コピー漏れがないか、もう一度確認して貼り付けてね${RESET}"
        WEBS_AI_GATEWAY_BASE_URL=""
        ;;
    esac
    if [ -z "$WEBS_AI_GATEWAY_BASE_URL" ] && [ "$url_attempt" -ge 3 ]; then
      echo
      warn "${BOLD}3 回うまくいかなかったよ。メンターさんを呼んで一緒に確認してもらおう 🙋${RESET}"
      echo
    fi
  done

  # --- ② アクセスキー（AI_GATEWAY_KEY）※必須 ---
  ACCESS_KEY=""
  login_attempt=0
  while [ -z "$ACCESS_KEY" ]; do
    login_attempt=$((login_attempt + 1))
    echo
    printf "%b\n" "  ${ORANGE}${BOLD}② アクセスキー（AI_GATEWAY_KEY）${RESET}"
    printf "%b\n" "  ${DIM}メンターさんに『アクセスキーは？』って聞いてね${RESET}"
    printf "%b\n" "  ${DIM}（「sk-aipf-」で始まる長い文字列だよ。貼り付けたら Enter）${RESET}"
    printf "%b" "  ${ORANGE}アクセスキー:${RESET} "
    read -r ACCESS_KEY
    ACCESS_KEY="$(printf '%s' "$ACCESS_KEY" | tr -d '[:space:]')"
    case "$ACCESS_KEY" in
      sk-aipf-*)
        : # OK
        ;;
      "")
        fail "アクセスキーが入力されなかったよ 💦"
        ACCESS_KEY=""
        ;;
      *)
        warn "アクセスキーの形式が違うみたい（「sk-aipf-」で始まるはずだよ）"
        printf "%b\n" "  ${DIM}コピー漏れがないか、もう一度確認して貼り付けてね${RESET}"
        ACCESS_KEY=""
        ;;
    esac
    if [ -z "$ACCESS_KEY" ] && [ "$login_attempt" -ge 3 ]; then
      echo
      warn "${BOLD}3 回うまくいかなかったよ。メンターさんを呼んで一緒に確認してもらおう 🙋${RESET}"
      echo
    fi
  done

  # --- ③ Claude Code のモデル名（→ ANTHROPIC_MODEL）※必須・"sonnet" を含むこと ---
  # 取り違え防止のバリデーション: Claude Code 用はメイン会話モデル（sonnet）なので、貼られた文字列に
  # "sonnet" が含まれることを確認する（含まれなければ入れ直し）。値そのものは固定しない（メンター配布値）。
  WEBS_AI_MODEL=""
  model_attempt=0
  while [ -z "$WEBS_AI_MODEL" ]; do
    model_attempt=$((model_attempt + 1))
    echo
    printf "%b\n" "  ${ORANGE}${BOLD}③ Claude Code のモデル名${RESET}"
    printf "%b\n" "  ${DIM}メンターさんに『Claude Code 用のモデル名は？』って聞いて、そのまま貼り付けてね${RESET}"
    printf "%b\n" "  ${DIM}（\"sonnet\" が入ってる長い名前だよ。貼り付けたら Enter）${RESET}"
    printf "%b" "  ${ORANGE}Claude Code モデル名:${RESET} "
    read -r _in_model
    _in_model="$(printf '%s' "$_in_model" | tr -d '[:space:]')"
    _in_model_lc="$(printf '%s' "$_in_model" | tr 'A-Z' 'a-z')"
    if [ -z "$_in_model" ]; then
      fail "モデル名が入力されなかったよ 💦"
    else
      case "$_in_model_lc" in
        *sonnet*)
          WEBS_AI_MODEL="$_in_model"
          ok "Claude Code モデルを設定したよ"
          ;;
        *)
          warn "これは Claude Code 用じゃないかも（\"sonnet\" が入ってるはず）。もう一度確認してね"
          ;;
      esac
    fi
    if [ -z "$WEBS_AI_MODEL" ] && [ "$model_attempt" -ge 3 ]; then
      echo
      warn "${BOLD}3 回うまくいかなかったよ。メンターさんを呼んで一緒に確認してもらおう 🙋${RESET}"
      echo
    fi
  done

  # --- ④ サービス(API)のモデル名（→ ANTHROPIC_SMALL_FAST_MODEL / AI_GATEWAY_MODEL）※必須・"haiku" を含むこと ---
  # サービス(Sinatra 等)が使う軽量モデル。Claude Code の裏方(small/fast)にも同じ値を使う。"haiku" を含むことを確認。
  WEBS_AI_SMALL_FAST_MODEL=""
  apimodel_attempt=0
  while [ -z "$WEBS_AI_SMALL_FAST_MODEL" ]; do
    apimodel_attempt=$((apimodel_attempt + 1))
    echo
    printf "%b\n" "  ${ORANGE}${BOLD}④ サービス(API)のモデル名${RESET}"
    printf "%b\n" "  ${DIM}メンターさんに『API（サービス）用のモデル名は？』って聞いて、そのまま貼り付けてね${RESET}"
    printf "%b\n" "  ${DIM}（\"haiku\" が入ってる長い名前だよ。貼り付けたら Enter）${RESET}"
    printf "%b" "  ${ORANGE}API モデル名:${RESET} "
    read -r _in_api_model
    _in_api_model="$(printf '%s' "$_in_api_model" | tr -d '[:space:]')"
    _in_api_model_lc="$(printf '%s' "$_in_api_model" | tr 'A-Z' 'a-z')"
    if [ -z "$_in_api_model" ]; then
      fail "モデル名が入力されなかったよ 💦"
    else
      case "$_in_api_model_lc" in
        *haiku*)
          WEBS_AI_SMALL_FAST_MODEL="$_in_api_model"
          ok "API モデルを設定したよ"
          ;;
        *)
          warn "これは API 用じゃないかも（\"haiku\" が入ってるはず）。もう一度確認してね"
          ;;
      esac
    fi
    if [ -z "$WEBS_AI_SMALL_FAST_MODEL" ] && [ "$apimodel_attempt" -ge 3 ]; then
      echo
      warn "${BOLD}3 回うまくいかなかったよ。メンターさんを呼んで一緒に確認してもらおう 🙋${RESET}"
      echo
    fi
  done

  # --- 4 点セット（URL / キー / Claude Code モデル / API モデル）を保存（ヒアドキュメントは使わず printf）---
  mkdir -p "$(dirname "$WEBS_AI_CRED_FILE")"
  {
    printf '%s\n' "# Life is Tech! WebS AI - gateway config (auto-generated)"
    printf '%s\n' "# This file is private. Do NOT commit to git."
    printf "%s\n" "WEBS_AI_ACCESS_KEY='$ACCESS_KEY'"
    printf "%s\n" "WEBS_AI_GATEWAY_URL='$WEBS_AI_GATEWAY_BASE_URL'"
    printf "%s\n" "WEBS_AI_MODEL_ID='$WEBS_AI_MODEL'"
    printf "%s\n" "WEBS_AI_SMALL_FAST_MODEL_ID='$WEBS_AI_SMALL_FAST_MODEL'"
  } > "$WEBS_AI_CRED_FILE"
  chmod 600 "$WEBS_AI_CRED_FILE"

  unset _in_url _in_model _in_model_lc _in_api_model _in_api_model_lc login_attempt model_attempt apimodel_attempt
}

# ---------- 認証ループ：入力 → 保存 → エクスポート → 接続確認 → 失敗なら再入力 ----------
# 保存済みキーがあれば最初の試行でそれを使う。接続確認（webs_validate_key）に失敗した
# 場合（失効・期限切れ・コピーミス・接続先 URL 不一致など）は、そのキーを破棄して
# もう一度入力を促す。これにより「古い/無効なキーがキャッシュされたまま 403 で詰まる」
# 状態を自動で回復する（接続先 URL は上で既に最新へ上書き済み）。
auth_loop_attempt=0
while true; do
  # --- 接続情報を用意（保存済みキーが無ければ 4 点セットを 1 つずつ入力させて保存）---
  if [ -z "$ACCESS_KEY" ]; then
    webs_prompt_gateway_config
  fi

  # --- 環境変数をエクスポート（URL / キー / 2 モデルをまとめて最新値へ上書き）---
  echo
  step "AI を動かす準備中..."
  export ANTHROPIC_BASE_URL="$WEBS_AI_GATEWAY_BASE_URL"
  export ANTHROPIC_AUTH_TOKEN="$ACCESS_KEY"
  export ANTHROPIC_MODEL="$WEBS_AI_MODEL"
  export ANTHROPIC_SMALL_FAST_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
  export AI_GATEWAY_MODEL="$WEBS_AI_SMALL_FAST_MODEL"
  export AWS_REGION="$WEBS_AI_REGION"

  # --- 接続確認（このキーで実際にゲートウェイを通れるか）---
  step "AI ゲートウェイに接続できるか確認中..."
  webs_check_result="$(webs_validate_key)"
  case "$webs_check_result" in
    ok|skip)
      ok "接続確認 OK！準備オッケー ✨"
      dim "次回からは自動でこのアクセスキーを使うよ"
      # 次回以降は毎回 source しなくて済むよう、rc に自動ロード行を登録（冪等）。
      webs_install_autoload
      break
      ;;
    auth)
      # 失効/無効キー（または URL 不一致）→ 保存キーを破棄して再入力させる（自己回復）
      echo
      fail "このアクセスキーでは接続できなかったよ（失効・期限切れ・コピーミスかも）💦"
      dim "保存していたキーは消したよ。最新のアクセスキーをもう一度貼り付けてね"
      rm -f "$WEBS_AI_CRED_FILE"
      unset ANTHROPIC_AUTH_TOKEN
      ACCESS_KEY=""
      auth_loop_attempt=$((auth_loop_attempt + 1))
      if [ "$auth_loop_attempt" -ge 3 ]; then
        echo
        warn "${BOLD}何度やっても繋がらないみたい。メンターさんを呼んでね 🙋${RESET}"
        dim "（キーが発行し直されているか、接続先 URL の確認が必要かもしれません）"
        echo
        return 1 2>/dev/null || exit 1
      fi
      ;;
    *)
      # ネットワーク不通など。キーの問題とは断定できないのでキーは保持する。
      echo
      warn "ゲートウェイに接続できなかったよ（ネットワークの問題かも）。キーはそのまま保持するね"
      dim "通信環境を確認して、もう一度 source し直してみてね"
      break
      ;;
  esac
done

# ---------- ルール系ファイルを read-only に ----------
echo
step "大事な設定ファイルを保護中..."
RULES_DIR="$WEBS_AI_TEMPLATE_DIR/.claude/.rules"
SKILLS_DIR="$WEBS_AI_TEMPLATE_DIR/.claude/skills"
AGENTS_DIR="$WEBS_AI_TEMPLATE_DIR/.claude/agents"

protect_count=0
if [ -d "$RULES_DIR" ]; then
  find "$RULES_DIR" -type f -name "*.md" -exec chmod 444 {} \; 2>/dev/null
  count=$(find "$RULES_DIR" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  protect_count=$((protect_count + count))
fi
if [ -d "$SKILLS_DIR" ]; then
  find "$SKILLS_DIR" -type f -name "SKILL.md" -exec chmod 444 {} \; 2>/dev/null
  count=$(find "$SKILLS_DIR" -type f -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  protect_count=$((protect_count + count))
fi
if [ -d "$AGENTS_DIR" ]; then
  find "$AGENTS_DIR" -type f -name "*.md" -exec chmod 444 {} \; 2>/dev/null
  count=$(find "$AGENTS_DIR" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  protect_count=$((protect_count + count))
fi

if [ "$protect_count" -gt 0 ]; then
  ok "OK！$protect_count 個のファイルを大事にしまったよ"
fi

# ---------- Claude Code の初回対話画面（テーマ / 信頼 / 権限）を先回りでスキップ ----------
echo
step "Claude の初回セットアップを自動で済ませておくよ..."
webs_setup_claude_defaults

# ---------- サービス用の gem を用意（Gemfile があれば bundle install）----------
echo
webs_bundle_install

# ---------- ログアウトコマンド `webs-logout` ----------
# ログアウト処理はこのスクリプト内の webs-logout 関数として定義済み。
# source で読み込まれていれば、その関数が現在のシェルにそのまま残るので、
# 追加のエイリアス登録は不要（`webs-logout` で呼べる）。

# ---------- 完了 ----------
echo
printf "%b\n" "${GREEN}${BOLD}  ✨ ぜんぶ準備できたよ！ ✨${RESET}"
echo

export WEBS_AI_INITIALIZED=1
