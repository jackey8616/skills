# Skills

給真實工程工作用的 agent skills：用訪談把想法問清楚、轉成規格與工單、測試先行地做出來，再回頭審查做出了什麼。

它們是純 Markdown，不是框架。每一個都短到能一次讀完、隨手改成你要的樣子；它們彼此組合，而不是接管你的流程。27 個 skill，支援 Claude Code、Codex，以及其他相容 Agent Skills 的 harness。

## 安裝

把 repo clone 下來，再把每個 skill 連結進本機的 harness 目錄：

```bash
git clone git@github.com:jackey8616/skills.git
cd skills
scripts/link-skills.sh
```

這會把每個 skill 以 symlink 連進 `~/.claude/skills` 和 `~/.agents/skills`。因為是連回這份 clone 的 symlink，`git pull` 一次就更新所有已安裝的 skill，而在這裡改動下次呼叫就生效。新增、刪除或改名 skill 之後，重跑這個腳本。

接著，在每個你想用它們的 repo 裡各跑一次：

```
/setup-skills
```

它會問這個 repo 用哪個 issue tracker、`/triage` 要套哪些標籤、文件要放哪裡，然後初始化工程流程會寫入的 spec layer（`openspec/`）。

### Claude Code cloud container

cloud container 是 ephemeral 的：每個 session 都是全新的 clone，`~/.claude/skills` 是空的。[.claude/settings.json](.claude/settings.json) 裡 commit 了一個 `SessionStart` hook，所以在這個 repo 上開的 session 會在第一個 turn 之前就把所有 skill 連好，不用打任何東西。

如果 session 是開在*別的* repo 上，就在那個 repo 自己的 hook、或該 environment 的 setup script 裡把這份 clone 下來再連結：

```bash
git clone --depth 1 https://github.com/jackey8616/skills.git ~/skills 2>/dev/null \
  || git -C ~/skills pull --ff-only
bash ~/skills/scripts/link-skills.sh
```

連結在跑它的那個 session 當下就生效，不必重開。model-invoked 的 skill 會立刻出現在清單裡；user-invoked 的一樣裝好了，只是不會出現在清單上，直接打斜線指令就行（[原因](docs/engineering/ask.md)）。

## skill 怎麼被叫到

skill 只分一個軸：誰能呼叫它。

**User-invoked** 的 skill 只有你打出來才會跑，例如 `/grill-me`。它們負責調度：驅動其他 skill，並問你那些只有你能回答的問題。

**Model-invoked** 的 skill 你可以打，agent 也會在任務對得上時自己去拿。它們裝的是可重複使用的紀律：訪談原語、審查、設計詞彙。

user-invoked 的 skill 可以呼叫 model-invoked 的。它永遠不能叫到另一個 user-invoked 的 —— 這條界線讓調度只留在一個地方。

## 主流程

多數工作走同一條路線。每一步留下的是檔案而不是對話，所以步驟之間可以清掉 context。

| 步驟                   | Skill                          | 留下什麼                                              |
| ---------------------- | ------------------------------ | ----------------------------------------------------- |
| 把想法問清楚           | `/grill-with-docs`             | `CONTEXT.md` 裡的詞彙、ADR，以及寫成文的提案           |
| 拆開它 —— 跨 session 的建置才需要 | `/to-spec`，接著 `/to-tickets` | 差異規格，接著 `tasks.md` 裡的曳光彈工單               |
| 做出來                 | `/implement`                   | 每張工單一個 commit，內部驅動 `/tdd`，收尾跑 `/code-review` |
| 收掉它                 | `/change-review`               | 歸檔 —— 唯一會更新「現況行為」的一步                   |

有三種情境是併入這條路線、而不是從頭走：issue 堆積（`/triage`）、東西壞了（`/diagnosing-bugs`）、以及大到一個 session 裝不下的迷霧工作（`/wayfinder`，它會畫出一張決策工單的地圖，最後在 `/to-spec` 匯回主線）。

真正有意思的是那些分支，而表格裝不下它們 —— 什麼時候小到可以跳過拆解、什麼時候一個問題得靠 prototype 才答得出來、該在哪裡切斷 context。**`/ask` 就是統管這一切的路由器。** 不確定該用哪個 skill 的時候就打它。

## 它們是為了解決什麼

每個 skill 對應一種跟 agent 一起開發時反覆出現的失敗模式：

- **對不齊。** agent 做錯東西，是因為沒有人把對的東西講精確。解法是在寫任何程式碼之前先訪談 —— `/grill-me`，或在有 repo 可以記錄答案時用 `/grill-with-docs`。
- **沒有共同語言。** 被丟進一個陌生專案，agent 會用二十個字講團隊只用一個詞的東西。`CONTEXT.md` 裡的詞彙表讓雙方用同一組名詞，這會縮短之後的每一次 session，也讓命名一致。由 `/domain-modeling` 維護。
- **沒有回饋迴路。** 少了一個會因為真正的問題而失敗的訊號，agent 等於瞎寫。`/tdd` 一次一個切片跑紅燈綠燈；`/diagnosing-bugs` 在有指令能重現這個 bug 之前，拒絕開始猜。
- **熵。** agent 加速產出的同時也一樣加速混亂。`/codebase-design` 提供深模組的詞彙，`/improve-codebase-architecture` 則掃過整個 codebase，找出值得加深的地方。

## Engineering

日常的程式工作。

**User-invoked**

- **[ask](./skills/engineering/ask/SKILL.md)** — 問哪個 skill 或流程適合你現在的處境。統管這個 repo 所有 skill 的路由器。
- **[grill-with-docs](./skills/engineering/grill-with-docs/SKILL.md)** — 訪談 session，同時建立專案的領域模型：把術語磨進 `CONTEXT.md`、把難以反轉的決策記成 ADR，最後寫出這次變更的提案作收。
- **[triage](./skills/engineering/triage/SKILL.md)** — 讓 issue 走過一套分類角色的狀態機。
- **[improve-codebase-architecture](./skills/engineering/improve-codebase-architecture/SKILL.md)** — 掃描 codebase 找出可以加深的機會，用視覺化 HTML 報告呈現，再針對你挑的那一個做訪談。
- **[setup-skills](./skills/engineering/setup-skills/SKILL.md)** — 把這個 repo 設定成能用這些工程 skill（issue tracker、triage 標籤、領域文件配置）。每個 repo 在使用其他工程 skill 之前跑一次。
- **[to-spec](./skills/engineering/to-spec/SKILL.md)** — 把談定的提案轉成一次 OpenSpec 變更的差異規格，並發一張指向它的 tracker issue。不做訪談 —— 只是把你已經討論過的東西整合起來。
- **[to-tickets](./skills/engineering/to-tickets/SKILL.md)** — 把一次變更拆成曳光彈工單，每張都聲明自己的阻擋邊 —— 寫進該變更的 `tasks.md` 作為單一事實來源，再從那裡切成一張張 issue。
- **[implement](./skills/engineering/implement/SKILL.md)** — 依照規格或一組工單把東西做出來，在事先談好的接縫上驅動 `/tdd`，並在 commit 之前以 `/code-review` 收尾。
- **[change-review](./skills/engineering/change-review/SKILL.md)** — 變更歸檔前的閘門：把 `tasks.md` 與 tracker 對帳，從涵蓋度（Coverage）與忠實度（Fidelity）兩軸審查整個變更，然後歸檔進 `openspec/specs/` —— 唯一會更新現況行為的一步。
- **[wayfinder](./skills/engineering/wayfinder/SKILL.md)** — 把一大塊超過單一 agent session 能裝下的工作，規劃成 issue tracker 上一張共享的決策工單地圖 —— 一次解一張，直到通往終點的路變清楚。

**Model-invoked**

- **[prototype](./skills/engineering/prototype/SKILL.md)** — 做一個用完即丟的原型來回答一個設計問題 —— 狀態／邏輯問題就做成一個可分享的單一 HTML 檔，UI 問題就做幾個差異極大、能從同一個 route 切換的版本。
- **[diagnosing-bugs](./skills/engineering/diagnosing-bugs/SKILL.md)** — 對付難纏 bug 與效能退化的紀律化診斷迴路：先建立一個會對這個 bug 亮紅燈的回饋迴路 → 最小化 → 提假設 → 加測量 → 修 → 補迴歸測試。
- **[research](./skills/engineering/research/SKILL.md)** — 針對高可信度的第一手來源調查一個問題，把發現寫成一份附引用的 Markdown 檔留在 repo 裡，以背景 agent 執行。
- **[tdd](./skills/engineering/tdd/SKILL.md)** — 紅燈綠燈重構迴路的測試驅動開發。一次一個垂直切片地做功能或修 bug。
- **[domain-modeling](./skills/engineering/domain-modeling/SKILL.md)** — 主動建立並磨利專案的領域模型 —— 拿詞彙表挑戰用詞、用邊界情境壓力測試、讓 `CONTEXT.md` 保持是一份詞彙表，並把行為描述導離 ADR，好讓 ADR 能維持凍結。
- **[writing-proposals](./skills/engineering/writing-proposals/SKILL.md)** — 開一次 OpenSpec 變更並寫下它的提案 —— 問題、談定的解法、被排除的選項 —— 外加 `design.md` 中權衡取捨的那一半。不做訪談：它只是把另一個 skill 已經談定的東西寫下來，而這正是 `grill-with-docs` 和 `wayfinder` 能用同一種方式收尾的原因。
- **[codebase-design](./skills/engineering/codebase-design/SKILL.md)** — 設計深模組的共同紀律與詞彙：小介面後面藏大量行為，放在乾淨的接縫上，並且能透過那個介面測試。
- **[code-review](./skills/engineering/code-review/SKILL.md)** — 從某個固定基準點起算的 diff 做雙軸審查：**Standards**（有沒有遵守這個 repo 的程式碼規範，外加一套 Fowler 壞味道基準）與 **Spec**（有沒有忠實實作原始的 issue／規格），以平行子 agent 執行，兩邊互不汙染。
- **[resolving-merge-conflicts](./skills/engineering/resolving-merge-conflicts/SKILL.md)** — 一段一段處理進行中的 git merge 或 rebase 衝突，依循各方第一手來源所追溯到的意圖來解，然後把操作做完 —— 絕不 `--abort`。
- **[wizard](./skills/engineering/wizard/SKILL.md)** — 產生一個互動式 bash 精靈，帶著人走過只有人能做的步驟：開通基礎設施、設定憑證或 CI secrets、操作不熟的第三方後台、執行一次性的搬遷或切換。

## Productivity

通用的工作流工具，跟程式碼無關。

**User-invoked**

- **[grill-me](./skills/productivity/grill-me/SKILL.md)** — 針對一份計畫或設計被毫不留情地訪談，直到決策樹的每一條分支都有結論。
- **[handoff](./skills/productivity/handoff/SKILL.md)** — 把當前對話壓縮成一份交接文件，讓另一個 agent 能接手繼續。
- **[teach](./skills/productivity/teach/SKILL.md)** — 跨多次 session 教你一項技能或概念，把當前目錄當成有狀態的教學工作區。
- **[to-questionnaire](./skills/productivity/to-questionnaire/SKILL.md)** — 把一個你無法獨自決定的決策，變成一份 Markdown 問卷給那個唯一能決定的人 —— 非同步填寫，或開會一起填。它訪談的是這次遞送（要給誰、你需要拿回什麼），而不是主題本身。
- **[wait-what](./skills/productivity/wait-what/SKILL.md)** — 訊息一沒聽懂就馬上丟這個。agent 會補上你缺的脈絡、用白話、以你 `CONTEXT.md` 的詞彙重講一次。

**Model-invoked**

- **[grilling](./skills/productivity/grilling/SKILL.md)** — 針對一份計畫、決策或想法毫不留情地訪談使用者，直到決策樹的每一條分支都有結論。這是 `grill-me`、`grill-with-docs`、`triage`、`wayfinder` 和 `improve-codebase-architecture` 背後那個可重複使用的訪談原語。
- **[writing-for-agents](./skills/productivity/writing-for-agents/SKILL.md)** — 寫給 agent 讀的文件：skill、AGENTS.md／CLAUDE.md，以及任何 agent 靠指標找到的文件。

## 在這個 repo 上工作

每個 skill 是一個資料夾，裡面有 `SKILL.md`、一份給 Codex 的 `agents/openai.yaml` 中繼資料，以及它按需揭露的參考檔案。每個 skill 在 `docs/` 底下都有一頁給人看的說明。房規放在 `.agents/`，這個 repo 自己的詞彙在 `CONTEXT.md`，agent 需要的規則在 `CLAUDE.md` —— `AGENTS.md` 是它的 symlink。

沒有東西要 build、要測、要安裝。改 `SKILL.md` 會立刻改到已安裝的 skill，因為安裝就是 symlink。

## Credits

這些 skill 源自 Matt Pocock 的 [mattpocock/skills](https://github.com/mattpocock/skills)，MIT 授權。這個 repo 是一份脫離的 fork：不追蹤上游、不發布 plugin，並在其之上帶著自己的修改。那些修改的著作權屬於 jackey8616 (Clooooode, Koli Mo)，採用相同授權 —— 兩份聲明都在 [LICENSE](./LICENSE) 裡。
