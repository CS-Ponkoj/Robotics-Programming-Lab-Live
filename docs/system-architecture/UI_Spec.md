# 03 · UI_Spec — Screens, Layout and Visual Rules

> **What this file answers:** *What does each screen look like, how does it adapt to the screen size, and what visual rules keep it consistent?*
>
> | Blueprint | [PRD](PRD.md) · [AppFlow](AppFlow.md) · [UI_Spec](UI_Spec.md) · [TRD](TRD.md) · [Schema](Schema.md) · [Plan](Plan.md) |
> |---|---|
> | Describes | Live release `a69b89b3` (Flutter web) |
> | Last reviewed | 2026-11-20 |

---

## 1. Design principles

| Principle | In practice |
|---|---|
| **Learning first** | The instructions keep their full height. Results open as a separate panel instead of pushing the instructions down |
| **Calm and clear** | Light grey page with white cards. One brand gradient per account (see §5), and a purple accent only for AI-generated content |
| **Honest feedback** | Results name the failed check, the student's own line, and what to try next |
| **Works everywhere** | Desktop, tablet and phone widths share one codebase |
| **Accessible** | Keyboard reachable, labelled controls, live-region messages, readable contrast |

## 2. Screen inventory

| Screen | File | Who | Purpose |
|---|---|---|---|
| Login | [`login_page.dart`](../../frontend/lib/screens/login_page.dart) | Everyone | Sign in, try the demo. No demo credentials are shown |
| Home | [`assignment_list.dart`](../../frontend/lib/screens/assignment_list.dart) | Signed in | **Assignments** and **Contents** tabs, progress cards |
| Assignment workspace | [`assignment_workspace.dart`](../../frontend/lib/screens/assignment_workspace.dart) | Signed in | Instructions, code editor, terminal, results |
| Course contents | [`course_content_page.dart`](../../frontend/lib/screens/course_content_page.dart) | Signed in | Topic sections and quizzes |
| My account | [`my_account_page.dart`](../../frontend/lib/screens/my_account_page.dart) | Not demo | Change password |
| My study progress / Research dashboard | [`research_dashboard_page.dart`](../../frontend/lib/screens/research_dashboard_page.dart) | Student / Instructor | Own progress / class analytics and export |
| Instructor Studio | [`instructor_assignment_admin.dart`](../../frontend/lib/screens/instructor_assignment_admin.dart) | Instructor | Hub for assignments, accounts, research and feedback |
| Manage accounts | [`student_accounts_page.dart`](../../frontend/lib/screens/student_accounts_page.dart) | Instructor | Add, import, deactivate and reset accounts; set each student's feedback mode (coloured pill on the card, picker in New account and Edit details) |
| AI tutor settings | [`ai_tutor_settings_page.dart`](../../frontend/lib/screens/ai_tutor_settings_page.dart) | Instructor | Course switch, daily limit, reviewed assignments |
| Sign-in history | [`sign_in_history_page.dart`](../../frontend/lib/screens/sign_in_history_page.dart) | Instructor | Recent sign-ins per account |
| Feedback inbox | [`feedback_inbox_page.dart`](../../frontend/lib/screens/feedback_inbox_page.dart) | Instructor | Page feedback from users |

## 3. The assignment workspace (key screen)

### Desktop (width ≥ 900 px)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ ← Back to assignments    Assignment 3: Multi-Floor Office      [Feedback] [?] │
├───────────────────────────────┬──────────────────────────────────────────────┤
│  INSTRUCTIONS                 │  CODE                     [Run] [Try inputs] │
│  ▸ Scenario                   │  ┌───┬──────────────────────────────────┐    │
│  ▸ Your task                  │  │ 1 │ def plan_route(...):             │    │
│  ▸ Rules, scoring, and checks │  │ 2 │     ...                          │    │
│  [diagram — tap to enlarge]   │  └───┴──────────────────────────────────┘    │
│                               │  ═══ drag to resize ═══                      │
│  (keeps full height)          │  TERMINAL ▾  "2 of 4 checks passed"          │
│                               │  > printed output, error on your line ...    │
└───────────────────────────────┴──────────────────────────────────────────────┘
                                             ┌─────────────────────────┐
                                             │ RESULTS            [–]  │ ← right-side
                                             │ ✔ check 1  ✘ check 2    │   overlay,
                                             │ Hints 1–4 · Solution    │   minimizable
                                             └─────────────────────────┘
```

### Phone (width < 900 px)

```text
┌──────────────────────────┐
│ ←  Assignment 3     [⋯]  │
├──────────────────────────┤
│ [ Instructions | Code ]  │ ← tabs instead of side by side
├──────────────────────────┤
│ File: controller.py  ▾   │ ← one-line file picker (ROS projects)
│ ┌──┬───────────────────┐ │
│ │ 1│ ...               │ │
│ └──┴───────────────────┘ │
│ TERMINAL ▾               │
├──────────────────────────┤
│        [ Run ]           │
└──────────────────────────┘
```

### Workspace parts

| Part | Behaviour |
|---|---|
| **Instructions** | Collapsible sections (Scenario · Your task · Rules, scoring, and checks). Diagrams use version-specific image URLs and open enlarged |
| **Editor** | Python highlighting with a line gutter that scrolls with the code, find/replace, format, font size, light/dark editor toggle (dark by default), and an option to restore the starter code |
| **Earlier-version banner** | Appears when a draft exists for an older version. **View and copy** or **Dismiss** |
| **Terminal** | Collapsible and resizable. Shows printed output, the error on the student's line, and a summary such as "· code changed since" |
| **Results overlay** | Right side, can be minimized and keeps its content when reopened. Shows checks, hints and the solution approach |
| **Try inputs dialog** | Call the function with your own values, including fractions such as `1/3`. Not graded or saved. Warns when the inputs changed after the shown result |
| **Simulation** | Square panel with a 2D replay of the student's ROS 2 node (Arena, LiDAR, Charts, Ranges). Visual only, never graded |
| **AI tutoring** | Toggle off by default, and every AI answer is labelled. When AI is unavailable, the built-in hints remain. One tutor reply is one card: the hint, then what to inspect, debugging steps and the next action. The Ask the tutor answer card appears only after a question |

### What each feedback mode shows

The server trims each result to the account's mode; the app hides controls the
mode cannot use. Grading is the same in every mode.

| Part | Traditional | TDD | TDD + AI | Instructor |
|---|---|---|---|---|
| Score, points, "checks passed: n of m" | ✅ | ✅ | ✅ | ✅ |
| Error at the student's own line | ✅ | ✅ | ✅ | ✅ |
| Check names, messages, test details | — | ✅ | ✅ | ✅ |
| Printed output (terminal says it is not part of the feedback) | — | ✅ | ✅ | ✅ |
| Built-in hint ladder | — | ✅ | ✅ | ✅ |
| Simulate button and Simulation panel | — | ✅ | ✅ | ✅ |
| AI button (tutoring on/off), AI hint, Ask the tutor | — | — | ✅ | ✅ |

## 4. Responsive breakpoints

| Width | Layout change |
|---|---|
| ≥ 1180 px | Home content capped at 1180 px wide |
| ≥ 900 px | Workspace side by side; Home shows a grid of assignment cards |
| ≥ 850 px | Course topics in multiple columns |
| < 720 px | Home cards stack in one column |
| < 600 px | Compact headers; the Feedback button shows only an icon |
| < 480 px | Workspace toolbar condenses |

## 5. Visual language

### Colour tokens ([`app_theme.dart`](../../frontend/lib/theme/app_theme.dart))

**Brand palettes.** `brand`, `brandDark`, `brandDeep`, `brandTint` and the
header/button gradient come from the signed-in account
(`BrandPalettes.forAccount`). Instructors use bronze, the signed-out sign-in
page uses teal, and students use their feedback mode's palette. Headers (`BrandHeaderGradient`) and filled
buttons run left to right from the gradient start to its end; tonal and
custom-coloured buttons stay flat.

| Palette | `brand` | Gradient | Tint |
|---|---|---|---|
| Traditional (blue) | `#2F5FA7` | `#1F4277` → `#3567B5` | `#DFE8F5` |
| TDD (green; also the demo) | `#2E7D4F` | `#1E5A37` → `#2F8554` | `#DFF0E5` |
| TDD + AI and signed out (teal) | `#19778C` | `#0F4C5C` → `#1A7F8E` | `#DDEFF2` |
| Instructor (bronze) | `#985B16` | `#7A3F0E` → `#985B16` | `#F7E9D7` |

White text is at least 4.5:1 on every gradient stop and every `brand`; a test
in `frontend/test/feedback_mode_test.dart` enforces it.

| Token | Hex | Used for |
|---|---|---|
| `brand` | per palette | Links, active tabs, icons, solid fallbacks |
| `brandDark` | per palette | Strong emphasis |
| `pageBackground` | `#EDF1F5` | App background |
| `border` | `#D3DBE4` | Card and panel edges |
| `ink` / `inkMuted` | `#16222E` / `#475766` | Body text / secondary text |
| `success` | `#18794E` | Passed checks |
| `performanceLow` | `#C62828` | Failed checks, low scores |
| `performanceMid` | `#9A5A00` | Partial scores, warnings |
| `ai` | `#5B46C2` | **Only** AI-generated content |
| `learningSurface` / `practiceSurface` / `insightSurface` | `#F0F8F7` / `#FFF5E6` / `#F5F2FC` | Lesson, exercise and insight cards |

**Spacing scale:** 4 · 8 · 16 px (`xs`, `sm`, `md`) and multiples.
**Fonts:** Lotion for the UI and Courier New for code.

### Status language

| State | Look | Example text |
|---|---|---|
| Passed | Green ✔ | "All 4 checks passed" |
| Partly passed | Amber | "2 of 4 checks passed" |
| Failed / error | Red ✘ | "Return exactly 3 values in this order: …" |
| Stale | Amber note | "Code changed since this run" |

## 6. Required UI states

Every screen that loads data must show each of these states:

| State | Requirement |
|---|---|
| Loading | A spinner with text, never an endless spinner (requests time out) |
| Empty | A friendly message, e.g. "No test results yet. Run assignment tests to see feedback." |
| Error / offline | A plain message plus **Try again** |
| Permission denied | A clear message. An expired sign-in shows the **Please sign in again** dialog |
| Double submit | Buttons are disabled while a request is running |

## 7. Accessibility checklist

- [x] All icon buttons have tooltips or semantic labels.
- [x] Result and error messages are announced through live regions.
- [x] Keyboard shortcuts are listed in the editor ("Keyboard shortcuts").
- [x] Light-mode code tokens get a thin outline for readability.
- [ ] Full screen-reader walkthrough of the workspace (not yet audited).
- [x] White text on every brand gradient stop is at least 4.5:1 (enforced by a test).
- [ ] Colour-contrast audit of the remaining token pairs (not yet audited).
