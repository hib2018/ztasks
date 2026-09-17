# ztasks

ztasks は、Spec Kit が生成した Task を Agent が実行するとき、その進捗を監視し、人間が途中で確認・介入するための Control Surface です。

一般的な Todo アプリや Planner ではありません。Task の内容を考えたり、Task Definition を独自に管理したりせず、Spec Kit の `tasks.md` を読み取り専用の Canonical Source として扱います。

```text
Human Request → zintent → Approved Intent → Spec Kit
                                              ├── spec.md
                                              ├── plan.md
                                              └── tasks.md
                                                    ↓
                                                 ztasks
                                                    ↕
                                             Human Control
                                                    ↕
                                             Agent Adapter
                                                    ↓
                                                  Agent
```

ztasks が扱うのは「何を実装すべきか」ではなく、次の問いです。

- 今どの Task が実行されているか
- Agent は何をしているか
- どこで停止または失敗しているか
- 人間がどのように介入するか
- 実行履歴から現在の状態を再現できるか

## 基本方針

ztasks は Human-controlled Artifact Pipeline を採用しています。Agent の内部推論を制御するのではなく、外部から確認できる Artifact と Event の境界を制御します。

```text
Agent Execution → Execution Event → ztasks → Human Intervention → Agent Adapter
```

主な原則は以下のとおりです。

- `tasks.md` は読み取り専用であり、ztasks は checkbox を含めて書き換えません。
- Task Definition と Runtime State を分離します。
- Event は append-only で保存し、現在の状態は Event の replay によって復元します。
- Frontend は表示と入力を担当し、状態遷移と不変条件は Core が検証します。
- Pi、Codex、Claude Code、Gemini CLI などの Agent 固有処理は Adapter に隔離します。
- Human Intervention の要求と、Agent による実際の反映を区別します。

## アーキテクチャ

```text
┌─────────────────────────────────────────────┐
│ Go Frontend                                 │
│ CLI / TUI / input / rendering / adapters    │
└──────────────────────┬──────────────────────┘
                       │ stdin/stdout JSON Lines
┌──────────────────────▼──────────────────────┐
│ Zig Core                                    │
│ source parsing / validation / transition    │
│ Event reducer / persistence / reconstruction│
└──────────────────────┬──────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │ Spec Kit source            │ .ztasks Runtime
        │ tasks.md (read-only)        │ events / state / artifacts
        └─────────────────────────────┘
```

Go と Zig は FFI ではなく process boundary を維持し、1行1 JSON object の JSON Lines Protocol で通信します。Core は単独で起動・テストでき、別の Frontend や Agent Adapter からも利用できます。

## Task の状態

| 状態 | 意味 |
|---|---|
| `pending` | 依存 Task の完了待ち |
| `ready` | 実行可能 |
| `running` | Agent が実行中 |
| `paused` | 人間または Agent により一時停止 |
| `blocked` | 判断、依存、外部要因待ち |
| `failed` | 実行失敗 |
| `completed` | 完了 |
| `skipped` | 意図的に実行しない |

状態遷移は Zig Core が検証します。Go Frontend や Adapter が不正な状態を直接作ることはできません。

## Event と Human Intervention

実行状況は `task.started`、`task.progress`、`task.paused`、`task.blocked`、`task.failed`、`task.completed`、`task.skipped`、`task.comment` などの Event として保存されます。

人間の操作も `human.pause_requested`、`human.resume_requested`、`human.retry_requested`、`human.stop_requested`、`human.skip_requested`、`human.comment` などの Event です。

介入要求を記録しただけでは、Task の lifecycle は変更されません。Adapter が Agent に作用し、acknowledgement または lifecycle Event を返した時点で結果が確定します。Agent や Harness が操作をサポートしていない場合も、その結果を履歴に残せます。

## インストール

Release archive は、互換性のある2つの実行ファイルを含みます。

```text
bin/ztasks
libexec/ztasks/ztasks-core
```

ユーザー所有の prefix へ一度インストールします。

```sh
./scripts/install.sh install "$HOME/.local" \
  ztasks-<version>-<os>-<arch>.tar.gz

export PATH="$HOME/.local/bin:$PATH"
```

Release archive からのインストールには Go や Zig の toolchain は不要です。Frontend は自身の配置場所を基準に bundled Core を検出し、Project を変更する前に product・Protocol・data version の互換性を検証します。

更新とアンインストール:

```sh
./scripts/install.sh update "$HOME/.local" ztasks-<version>-<os>-<arch>.tar.gz
./scripts/install.sh uninstall "$HOME/.local"
```

`ZTASKS_CORE` は開発・診断時に Core のパスを明示するための override です。

### Release archive の作成

```sh
./scripts/package.sh                 # 現在のOS/architecture
./scripts/package.sh darwin arm64
./scripts/package.sh linux amd64
```

archive と SHA-256 checksum は `dist/` に生成されます。対応 target は macOS/Linux の amd64/arm64 です。

## クイックスタート

Spec Kit の `tasks.md` が存在する Project で実行します。

```text
project/
├── specs/
│   └── 001-feature/
│       ├── spec.md
│       ├── plan.md
│       └── tasks.md
└── src/
```

```sh
cd project
ztasks init
ztasks status
ztasks task show T001
```

引数なしの `ztasks` は TUI を起動します。

```sh
ztasks
```

Spec Kit が `tasks.md` を更新したら、再同期します。

```sh
ztasks sync
```

`init` と `sync` は `tasks.md` を変更しません。正規化した Definition と dependency artifact を `.ztasks/sources/` に保存し、受理した同期ごとに監査可能な Event を1件追加します。変更がない同期も空の change set を持つ Event として記録されます。

## CLI

### 参照

```sh
ztasks status
ztasks status --json
ztasks task show T001
ztasks task show T001 --json
ztasks event list
ztasks event list T001
ztasks doctor
ztasks help
ztasks version
```

### Agent execution の記録

```sh
ztasks start T001
ztasks event emit --type task.progress --task T001 \
  --message "editing src/parser.zig"
ztasks block T001 "external API decision required"
ztasks fail T001 "test failed"
ztasks complete T001
```

`event emit` は任意 Event の注入機能ではありません。許可された operation/Event mapping のみを受け付け、transition の妥当性は Core が検証します。

### 人間による介入

```sh
ztasks pause T001
ztasks resume T001
ztasks comment T001 "この境界条件を先に確認してください"
ztasks retry T001
ztasks stop T001
ztasks skip T001
ztasks inspect T001
```

Agent 統合がなくても、状態参照、コメント、Event 履歴、doctor は利用できます。

## Runtime の保存

各 Project の Runtime は、その Project 自身の `.ztasks/` に保存されます。

```text
.ztasks/
├── events.jsonl     # append-onlyの監査・復元元
├── state.json       # 再構築可能なsnapshot
├── sources/         # digest-addressed Definition/dependency artifacts
├── sessions/        # session関連データ
├── view.json        # TUIの選択・filter設定のみ
└── write.lock       # writer排他制御
```

`events.jsonl` が Runtime の権威です。`state.json` は derived snapshot なので、古い場合や削除された場合は Event から再構築できます。`view.json` は表示設定だけを保存し、Task の Runtime State は含みません。

通常は Project の `.gitignore` に次を追加してください。

```gitignore
.ztasks/
```

監査要件がある場合は、一時的な snapshot や lock を Git に含めるのではなく、append-only の `events.jsonl` を管理された保存先へ複製してください。Event 履歴を手作業で編集しないでください。

## Source sync と復旧

- 追加された Task は依存関係から `pending` または `ready` を導出します。
- 既存 Task は Runtime lifecycle を保持したまま Definition を更新します。
- 削除された Task は履歴と最後の Definition を保持し、definition missing として扱います。
- 再出現した Task は既存 Runtime に再接続されます。
- 不正な source や永続化失敗は、直前の有効な projection を変更しません。
- Event commit 後に snapshot 更新が失敗しても、Event が権威として残ります。
- Event commit 前に作られた未参照 artifact は不活性であり、現在の projection にはなりません。

`ztasks doctor` は source、Event history、snapshot、artifact、lock、filesystem、互換性に関する診断を返します。自動修復できない問題でも、既存の監査履歴を破壊しません。

## セキュリティと観測可能性

Core は mutation payload を closed schema として検証し、private reasoning、transcript、raw stdout/stderr、credential container などの禁止 field を拒否します。許可された短いテキストに既知の credential 形式が含まれる場合は、Event ID や sequence を割り当てる前に `[REDACTED:<class>]` へ置換します。

ztasks は未知の秘密情報や Agent の内部推論を意味的に分類できるとは保証しません。Adapter と呼び出し側は、raw process output ではなく、短く確認可能で secret-free な action/result summary を送信してください。

## 開発

必要な toolchain:

- Zig 0.16
- Go 1.27

主要コマンド:

```sh
make fmt
make fmt-check
make test-core
make test-go
make test-contract
make test
make build
```

Go Frontend は transport、CLI/TUI、表示、Agent Adapter を担当します。Zig Core は source parsing、Task/Event model、state transition、validation、redaction、persistence、replay を担当します。原則は次の一文に集約されます。

> Frontend presents; core enforces.

Protocol は実装言語に依存しない契約です。operation/Event mapping、dependency extraction、source adapter、redaction rule を変更するときは、以下を同時に更新してください。

- Zig Core と Go Frontend
- `protocol/fixtures/` の共有 fixture
- `specs/001-task-execution-control/contracts/` の契約文書
- contract test と関連する E2E test

詳細な wire protocol は [protocol/README.md](protocol/README.md)、設計と検証シナリオは [feature artifacts](specs/001-task-execution-control/) を参照してください。

## 現在の範囲

- 対応する Task source は Spec Kit の `tasks.md` です。
- ztasks 自身は Task、Proposal、AI prompt を生成しません。
- GitHub Issue から Task を生成しません。
- `tasks.md` の自動 reconcile や checkbox 更新は行いません。
- Pi は主要な統合候補ですが、Core と Protocol は特定 Agent に依存しません。
- Agent プロセスへ強制的に作用できる範囲は、利用する Adapter/Harness の能力に依存します。
