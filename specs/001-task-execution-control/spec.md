# Feature Specification: Agent Task Execution Control

**Feature Branch**: `001-task-execution-control`

**Created**: 2026-09-12

**Status**: Draft

**Input**: User description: "Spec Kitが生成したTaskをAgentが実行する際に、その進捗を監視し、人間が途中で確認・介入できるControl Surfaceを提供する"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 実行状況を把握する (Priority: P1)

利用者は、Spec Kitで定義されたTaskを一覧し、現在実行中のTask、実行可能なTask、
依存Task待ちのTask、停止または失敗したTaskを一画面または一覧出力で確認する。
選択したTaskについて、担当Agent、実行セッション、現在の作業、停止理由、最終エラー、
最近のActivityを確認できる。

**Why this priority**: 実行状況を正確に把握できなければ、監視にも人間の介入にも使えないため。

**Independent Test**: 複数Phaseと依存関係を持つTask定義および実行履歴を読み込ませ、
利用者が各Taskの現在状態、実行中の作業、停止理由、最近のActivityを識別できることを確認する。

**Acceptance Scenarios**:

1. **Given** 有効なTask定義と実行履歴があるProjectで、**When** 利用者が全体状況を開く、
   **Then** TaskがPhase別に安定した順序で表示され、各Taskの現在状態を判別できる。
2. **Given** 実行中のTaskが選択されている状態で、**When** 利用者が詳細を表示する、
   **Then** Agent、session、開始時刻、現在の作業、最終更新、最近のActivityが表示される。
3. **Given** 依存Taskが未完了のTaskがある状態で、**When** 状況を表示する、
   **Then** そのTaskは実行可能と誤表示されず、満たされていない依存関係を確認できる。
4. **Given** Task定義だけがあり実行履歴がないProjectで、**When** 状況を表示する、
   **Then** 依存関係に応じた初期状態が表示される。

---

### User Story 2 - Agent実行を記録する (Priority: P2)

AgentまたはAgent Adapterは、Taskの開始、進捗、停止、再開、阻害、失敗、完了、
意図的なskip、commentを共通形式で記録する。記録された履歴から、現在状態を
一貫して復元できる。

**Why this priority**: Control Surfaceが実際のAgent実行を反映し、異なるAgentでも同じ方法で
監視できるために必要だから。

**Independent Test**: 1つのTaskへ正常系と失敗系のEvent列を投入し、許可された遷移だけが
受理され、同じ履歴を再読込すると同一の現在状態になることを確認する。

**Acceptance Scenarios**:

1. **Given** 実行可能なTaskがある状態で、**When** Agentが開始と複数の進捗を記録する、
   **Then** Taskは実行中となり、最新の作業内容と全Activityを確認できる。
2. **Given** 依存Task待ちのTaskがある状態で、**When** Agentが開始を記録しようとする、
   **Then** 記録は拒否され、未充足の依存Taskが示され、既存状態は変化しない。
3. **Given** 永続化済みのEvent履歴がある状態で、**When** 現在状態の保存情報を失って再読込する、
   **Then** Event履歴から同じTask状態が復元される。
4. **Given** 同じ記録要求が再送された状態で、**When** 再度処理される、
   **Then** 同一Eventが二重に適用されない。

---

### User Story 3 - 実行途中に介入する (Priority: P3)

利用者は実行中または停止中のTaskに対して、pause、resume、comment、retry、stop、
skip、inspectの要求を記録できる。要求と、Agentが実際に要求を受理・実行した結果は
区別して表示される。

**Why this priority**: 人間がAgent実行を監督し、判断が必要な箇所で方向修正できることが
ztasksの中心的価値だから。

**Independent Test**: 実行中Taskへpause要求を記録し、Agentから停止確認が届く前後を比較して、
要求中と停止済みが明確に区別されることを確認する。

**Acceptance Scenarios**:

1. **Given** AgentがTaskを実行中の状態で、**When** 利用者がpauseを要求する、
   **Then** pause要求がActivityへ記録され、TaskはAgentの確認まで停止済みと表示されない。
2. **Given** pause要求が保留中の状態で、**When** Agentが停止を確認する、
   **Then** Taskは停止中となり、要求と確認の関係を履歴から追跡できる。
3. **Given** 判断待ちで阻害されたTaskがある状態で、**When** 利用者がcommentを追加する、
   **Then** commentが対象Taskへ時系列で記録され、Agent Adapterが取得できる。
4. **Given** 失敗したTaskがある状態で、**When** 利用者がretryを要求する、
   **Then** retry要求は記録されるが、Agentが再実行を開始するまで実行中とは表示されない。

---

### User Story 4 - Projectを安全に再開・診断する (Priority: P4)

利用者は任意の対応Projectで監視状態を初期化し、Task定義の変更を再読込し、
再起動後も実行履歴と現在状態を確認できる。問題がある場合は、Task定義、履歴、
保存状態、互換性のどこに原因があるかを診断できる。

**Why this priority**: 長時間のAgent実行や中断を扱うには、再起動と障害後も監査可能である
必要があるため。

**Independent Test**: Projectを初期化して実行履歴を作成し、Task定義の追加・変更・削除と
不正データを順に与え、既存履歴を失わずに再開または診断できることを確認する。

**Acceptance Scenarios**:

1. **Given** Task定義を持つ未初期化Projectで、**When** 利用者が初期化する、
   **Then** Task定義自体を変更せず、Project固有のRuntime管理を開始できる。
2. **Given** Task定義に新しいTaskが追加された状態で、**When** 利用者が同期する、
   **Then** 既存TaskのRuntimeを維持したまま新しいTaskを監視対象へ加えられる。
3. **Given** Runtime履歴を持つTask IDがTask定義から消えた状態で、**When** 同期する、
   **Then** 履歴は削除されず、定義が見つからないTaskとして利用者に警告される。
4. **Given** Task定義または履歴が不正な状態で、**When** 利用者が診断する、
   **Then** 問題箇所と回復に必要な行動が示され、最後の有効な履歴は保持される。
5. **Given** 有効なTask定義の変更がある状態で、**When** 利用者が同期する、
   **Then** 同期の実行者、対象Source、変更前後の識別情報、追加・変更・消失・再出現した
   Task IDを含む同期Eventが記録され、そのEventから同期結果を監査できる。
6. **Given** Task定義の同期が検証または保存に失敗する状態で、**When** 利用者が同期する、
   **Then** 同期による状態変更Eventは記録されず、直前の有効な定義Projectionと履歴が維持される。
7. **Given** Task定義に明示的な依存記述、曖昧な依存記述、依存記述のないTaskが混在する状態で、
   **When** 利用者が同期する、**Then** 明示的な依存だけを根拠位置付きのmachine-readable artifactへ
   抽出し、曖昧または不在の依存は推測せず診断として確認できる。

---

### User Story 5 - 一度導入して複数Projectで利用する (Priority: P5)

利用者はztasksをProjectの外へ一度導入し、ztasksのRepositoryを各Projectへcloneしたり、
build用toolchainをProjectごとに準備したりせず、任意の対応Projectから監視を開始できる。
FrontendとCoreの欠落または互換性不一致がある場合は、安全に停止して修正方法を確認できる。

**Why this priority**: Projectごとの複製やbuild手順を要求すると、継続利用と複数Projectの監視を
妨げ、FrontendとCoreのversion不一致を見逃しやすくなるため。

**Independent Test**: ztasksもbuild toolchainも存在しないcleanな利用環境へ配布物を一度導入し、
2つの独立したfixture Projectから初期化、status表示、version診断を実行する。ztasksのSource cloneを
作らずに利用でき、両ProjectのRuntime履歴が分離され、互換性不一致時には変更前に停止することを確認する。

**Acceptance Scenarios**:

1. **Given** 対応環境へztasksを一度導入した状態で、**When** 利用者が有効なTask定義を持つ
   Projectからztasksを起動する、**Then** ztasksのSource cloneやbuild toolchainなしでそのProjectを
   対象として監視を開始できる。
2. **Given** 同じztasks installationを利用する2つのProjectがある状態で、**When** それぞれで
   Runtime Eventを記録する、**Then** 一方のProjectの履歴や設定が他方へ混入しない。
3. **Given** FrontendとCoreの互換性がない状態で、**When** 利用者が状態の参照または変更を試みる、
   **Then** ProjectのRuntimeを変更する前に処理が停止し、必要な更新または再導入方法が示される。
4. **Given** Core componentが見つからない状態で、**When** 利用者がztasksを起動する、
   **Then** 欠落したcomponentと修復方法を確認できる。

### Edge Cases

- 複数のTask定義に同じTask IDが存在する場合、同期を拒否し重複箇所を示す。
- 依存先のTask IDが存在しない場合、当該Taskを実行可能にせず定義エラーを示す。
- Task間の依存関係が循環する場合、同期を拒否し循環に含まれるTaskを示す。
- Task定義のcheckboxとRuntime状態が異なる場合、Runtime状態を上書きせず両者の違いを示す。
- 実行履歴に途中までしか書かれていない記録がある場合、最後に確定した記録までを保持し、
  破損位置を診断する。
- 同時に複数の利用者またはAgentが記録しようとした場合、履歴順序を一意に確定するか、
  一方を明示的に再試行可能な形で拒否する。
- 選択中のTaskが同期後に定義から消えた場合、その履歴への参照を維持して警告を表示する。
- Agentが介入要求へ応答しない場合、要求を保留中として表示し、完了したように見せない。
- Agentが対応していない介入を要求された場合、要求と非対応結果の両方を記録する。
- 非常に長い、Unicodeを含む、または制御文字を含むtitle/comment/progressを受け取った場合、
  有効な文字を安全に表示し、不正入力で画面や履歴を壊さない。
- 同期Eventの永続化後に現在状態の更新が中断された場合、同期Eventを正として再生し、同じ同期を
  二重に記録せず状態を復元する。
- 制限値ちょうどの入力と制限値を1単位超える入力を受け取った場合、同じ測定規則で前者を受理し、
  後者を状態や履歴を変更せず拒否する。
- 導入済みのFrontend、Core、またはprotocolの一部だけが更新された場合、互換性を推測せず、
  ProjectのRuntimeを変更する前に診断する。
- Task定義が変更された後に古いdependency artifactが残る場合、古い解析結果を利用せず、現在の
  Task定義から再生成するか安全に同期を拒否する。
- 許可されたcommentやprogressへ未知形式のsecretが含まれる場合、自動検出を保証せず、入力者へ
  secret-freeな要約を要求する一方、禁止fieldと認識可能なcredentialは保存前に拒否またはredactする。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST discover and read Spec Kit Task definitions from the current Project.
- **FR-002**: System MUST treat Task definition files as read-only and MUST NOT change their
  checkboxes, text, hierarchy, ordering, dependencies, or metadata.
- **FR-003**: System MUST represent Task Definition separately from Task Runtime and MUST use the
  Task ID from the definition as their association key.
- **FR-004**: System MUST extract, at minimum, each Task's ID, title, phase, source location,
  explicitly declared dependencies and their source evidence, parallel hint, and available
  metadata.
- **FR-005**: System MUST reject a definition set containing duplicate Task IDs, missing dependency
  targets, cyclic dependencies, invalid identifiers, or invalid text without changing the last
  valid Runtime state.
- **FR-006**: System MUST support the Runtime statuses pending, ready, running, paused, blocked,
  failed, completed, and skipped.
- **FR-007**: System MUST determine pending and ready consistently from Task dependencies and
  terminal states.
- **FR-008**: System MUST accept only defined status transitions and MUST reject an invalid
  transition without appending a state-changing Event.
- **FR-009**: System MUST record Task start, progress, pause confirmation, resume confirmation,
  blocked, failed, completed, skipped, and comment Events.
- **FR-010**: System MUST record human pause, resume, comment, retry, stop, skip, and inspect
  requests as Events distinguishable from Agent execution Events.
- **FR-011**: System MUST NOT treat a human intervention request as completed until an Agent or
  Adapter records the corresponding acknowledgement or result.
- **FR-012**: System MUST record for each Event a unique identity, stable order, type, timestamp,
  actor category, target Task when applicable, and typed event-specific details.
- **FR-013**: System MUST prevent a retried request with the same request identity from applying
  the same logical Event more than once.
- **FR-014**: System MUST preserve Events as an append-only Runtime history and MUST reconstruct
  the current Runtime State by replaying them.
- **FR-015**: System MUST keep any current-state snapshot subordinate to Event history and MUST
  recover when that snapshot is absent or stale.
- **FR-016**: System MUST ensure an accepted Event is durably recorded before publishing a derived
  current-state update.
- **FR-017**: System MUST preserve the last valid durable history when validation, storage,
  interruption, or concurrent access fails.
- **FR-018**: Users MUST be able to initialize Runtime monitoring for a Project without modifying
  its Task definitions.
- **FR-019**: Users MUST be able to rescan Task definitions and see added, changed, missing, and
  invalid Task IDs without silently deleting Runtime history.
- **FR-020**: Users MUST be able to list overall Task status and inspect one Task in both
  human-readable and machine-readable forms.
- **FR-021**: Users MUST be able to request valid Task actions and add comments through a
  command-oriented interface.
- **FR-022**: Authorized Agent integrations MUST be able to submit execution Events through the
  same validated public contract used by other integrations.
- **FR-023**: Users MUST be able to list all Events or filter Events by Task ID in stable order.
- **FR-024**: The interactive monitoring view MUST present Task list, selected Task execution
  detail, Activity, and available human interventions within one coordinated workspace.
- **FR-025**: The interactive view MUST distinguish pending requests, acknowledged actions,
  failures, blocked reasons, and stale Agent activity.
- **FR-026**: System MUST remain fully usable for manual monitoring and Event inspection without
  any particular Agent product being installed.
- **FR-027**: Agent-specific capabilities and failures MUST be reported without changing the
  generic meaning of Runtime statuses or intervention Events.
- **FR-028**: System MUST diagnose missing Task definitions, invalid definitions, corrupt or
  partial history, incompatible data, unavailable execution integration, and storage failures
  with actionable guidance.
- **FR-029**: System MUST provide discoverable help and version information even when the current
  Project is not initialized.
- **FR-030**: System MUST accept only Event-specific fields; reject fields designated for
  credentials, private Agent reasoning, unrestricted transcripts, or raw process output; redact
  recognized credential forms before persistence; never retain or echo original redacted values;
  and safely validate and render permitted text.
- **FR-031**: System MUST preserve Runtime data within its Project by default so that separate
  Projects do not share or overwrite execution history.
- **FR-032**: System MUST keep display preferences and Agent session details distinguishable from
  canonical Event history and derived Task Runtime.
- **FR-033**: Every accepted Task-definition synchronization MUST append exactly one immutable
  `source.synced` Event before publishing its resulting definition projection. The Event MUST
  identify the actor and source, the previous and accepted source revisions or digests, and the
  exact added, changed, missing, and reappeared Task IDs; an accepted no-change synchronization
  MUST be represented by empty change sets.
- **FR-034**: A rejected or incompletely persisted synchronization MUST NOT append a
  `source.synced` Event or publish a new definition projection, and MUST preserve the last valid
  definition projection and Runtime history.
- **FR-035**: System MUST enforce these field limits consistently at every public input boundary:
  Task and phase titles MUST contain at most 200 Unicode scalar values; actor and session
  identifiers MUST contain at most 128 UTF-8 bytes; comment, progress/current-action,
  blocked-reason, and error text MUST contain at most 4,096 UTF-8 bytes each; a source locator
  MUST contain at most 4,096 UTF-8 bytes; and one complete Event MUST contain at most 65,536
  UTF-8 bytes in its canonical serialized form.
- **FR-036**: System MUST reject required text that is empty, prohibited control content, or any
  field that exceeds its defined limit before changing durable history or current state, and MUST
  identify the rejected field and applicable limit without echoing sensitive content.
- **FR-037**: Users MUST be able to install ztasks once outside individual Projects and invoke it
  from any supported Project without cloning the ztasks source or installing build toolchains in
  that Project.
- **FR-038**: One installation MUST locate and use a compatible Frontend and Core while keeping
  Runtime data and configuration isolated by Project.
- **FR-039**: System MUST verify Frontend, Core, data, and protocol compatibility before any
  Project Runtime mutation and MUST provide actionable installation or update guidance when a
  required component is missing or incompatible.
- **FR-040**: System MUST generate a machine-readable dependency extraction artifact from the bound
  Task definition without modifying that definition.
- **FR-041**: The dependency artifact MUST identify the exact source revision, extraction-contract
  version, extracted Task dependency edges, source evidence for each edge, and diagnostics for
  ambiguous or absent dependency information.
- **FR-042**: System MUST produce byte-equivalent dependency meaning for the same Task definition
  and extraction-contract version, MUST reject or regenerate an artifact whose source revision does
  not match, and MUST remain correct if the artifact is deleted and regenerated.
- **FR-043**: System MUST NOT treat the dependency artifact as an independently editable Task
  Definition source and MUST NOT infer dependencies from Task numbering, Phase order, parallel
  hints, file overlap, or ambiguous prose.

### Key Entities *(include if feature involves data)*

- **Task Definition**: A read-only Task originating from Spec Kit, identified by a stable Task ID
  and carrying title, phase, dependency, ordering, source, and descriptive metadata.
- **Task Runtime**: The current execution projection associated with one Task ID, including status,
  Agent/session identity, timing, current action, blocked reason, last error, attempt, and pending
  intervention.
- **Event**: An immutable, ordered fact about Task execution, human intervention, acknowledgement,
  or commentary from which Runtime state can be reconstructed.
- **Actor**: The human, Agent, Adapter, or system component responsible for an Event.
- **Intervention Request**: A human-authored request to affect or inspect execution whose pending
  and acknowledged outcomes remain separately observable.
- **Task Source**: A provider of normalized Task Definitions; the initial supported source is a
  Spec Kit Task document.
- **Execution Session**: An optional association between Runtime Events and one Agent execution
  attempt, without imposing Agent-specific semantics on the Task model.
- **Runtime Snapshot**: A disposable acceleration artifact representing a known reduction point in
  Event history; it is not an independent authority.
- **Source Sync Event**: An immutable record that an exact Task Source revision and its normalized
  definition changes were accepted, allowing the active definition projection to be audited and
  reconstructed without making the source document writable.
- **Dependency Extraction Artifact**: A disposable, machine-readable projection of only explicit
  dependency information found in one exact Task Source revision, including evidence and
  diagnostics; it is not an independently editable definition authority.
- **Installation**: A compatible, user-accessible pairing of the human-facing application and the
  enforcing Core that can serve multiple Projects while leaving their Runtime data isolated.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a Project containing 500 Tasks and 10,000 Events, users can open the status view
  and identify the running, blocked, or failed Tasks within 2 seconds on a typical local machine.
- **SC-002**: For every tested valid Event sequence, rebuilding from Event history produces the
  same status, current action, attempt count, and pending intervention for 100% of Tasks.
- **SC-003**: For every tested invalid transition, malformed definition, duplicate request, and
  interrupted save, the last valid durable history remains readable and no invalid state is shown.
- **SC-004**: A user can locate a Task, inspect its current execution context, and submit a comment
  or pause request in no more than 30 seconds without leaving the monitoring workspace.
- **SC-005**: In usability verification, 90% of participants correctly distinguish a pending pause
  request from a confirmed paused state on their first attempt.
- **SC-006**: Re-reading changed Task definitions retains 100% of existing Runtime Events,
  including Events for Task IDs no longer present in the current definition.
- **SC-007**: The primary monitoring, history, and manual intervention workflows can be completed
  with no Agent integration installed.
- **SC-008**: A new Agent integration can report all standard execution Events and intervention
  outcomes without requiring changes to the generic Task Definition or Runtime status meanings.
- **SC-009**: Users can diagnose each defined source, history, compatibility, integration, and
  storage failure category from the reported message and suggested corrective action.
- **SC-010**: For 100% of tested accepted synchronizations, exactly one replayable sync Event is
  recorded and its Task-ID change sets match the resulting definition projection; rejected
  synchronizations record no sync Event and leave the prior projection unchanged.
- **SC-011**: Boundary tests for every bounded field accept values exactly at the stated limit and
  reject values one unit over it without changing durable history or current state.
- **SC-012**: On a clean supported user environment, a user can install ztasks once and begin
  monitoring an existing valid Project within 5 minutes without cloning ztasks or installing a
  build toolchain.
- **SC-013**: The same installation can operate against two independent Projects while 100% of
  recorded Runtime Events and Project settings remain associated only with their originating
  Project.
- **SC-014**: In all tested missing-component and compatibility-mismatch cases, ztasks detects the
  problem before a Runtime mutation and reports a corrective action.
- **SC-015**: For 100% of tested Task definitions, repeated extraction with the same contract
  version produces identical dependency meaning and evidence; deleting the generated artifact and
  regenerating it does not change any Task's readiness.
- **SC-016**: In all tested prohibited-field and recognized-credential cases, original protected
  values are absent from durable history, current-state data, user output, and diagnostics, while
  permitted secret-free summaries remain usable.

## Assumptions

- Spec Kit Task documents provide stable, unique Task IDs such as `T023`; renaming an ID is treated
  as removal of the old definition and addition of a new definition.
- Only dependency information explicitly declared in a form accepted by the active Task source
  contract is enforced. Phase ordering, Task numbering, parallel markers, file overlap, and
  ambiguous prose are never silently converted into dependencies.
- Definition checkboxes may be observed as source metadata but do not overwrite Runtime status.
- Completed and skipped Tasks satisfy dependencies; failed, paused, and blocked Tasks do not.
- Runtime monitoring is Project-local and intended for one trusted local user in the MVP.
- Event retention is indefinite by default. Export, archival, reconciliation, and destructive
  compaction are separate future features.
- Agent control remains best-effort because pause, resume, retry, stop, and skip capabilities vary
  by execution harness.
- A stop request has no separate terminal Task status in the MVP; the Agent reports the resulting
  failed/cancelled or skipped outcome.
- The initial release supports one Task source type, while preserving source-neutral Task entities.
- Task generation, planning, Proposal workflows, GitHub Issue ingestion, and automatic rewriting
  of Task definitions are outside this feature.
- The initial distribution targets supported operating-system and architecture combinations with
  prebuilt compatible Frontend and Core components; source builds remain an optional developer
  workflow rather than a per-Project requirement.
- The user can write to a personal executable/application directory and to each Project's local
  Runtime directory; system-wide installation is not required.
- Callers and Agent Adapters provide bounded, reviewable, secret-free summaries. Automatic
  credential recognition is defense in depth and is not assumed to classify arbitrary free text.
