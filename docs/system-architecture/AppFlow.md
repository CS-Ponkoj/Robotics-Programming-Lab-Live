# 02 · AppFlow — How People Move Through the App

> **What this file answers:** *Which screens exist, how does a user get from one to the next, and what happens at each step?*
> Layer 1 of the system blueprint, read together with [PRD.md](PRD.md).
>
> | Blueprint | [PRD](PRD.md) · [AppFlow](AppFlow.md) · [UI_Spec](UI_Spec.md) · [TRD](TRD.md) · [Schema](Schema.md) · [Plan](Plan.md) |
> |---|---|
> | Describes | Live release `3571938b` |
> | Last reviewed | 2026-10-26 |

---

## 1. Site map

Everyone lands on the same **Home** page (`AssignmentListPage`). The account
menu and the Instructor Studio button change with the role.

```mermaid
flowchart TD
    L[Login page] -->|login ID + password| H
    L -->|Try the student demo| H
    H[Home<br/>tabs: Assignments · Contents]

    H --> W[Assignment workspace]
    H --> C[Course contents<br/>topic → sections → quiz]
    H --> M{{Account menu}}

    M -->|not demo| ACC[My account<br/>change password]
    M -->|student| SP[My study progress]
    M -->|instructor| RD[Research study dashboard]
    M --> OUT[Log out → Login]

    H -->|instructor only| ST[Instructor Studio]
    ST --> AM[Assignment management<br/>create · validate · publish]
    ST --> SA[Manage accounts]
    SA --> SH[Sign-in history]
    ST --> RD
    ST --> FI[Feedback inbox]

    classDef inst fill:#3b2f5c,stroke:#8b7bd8,color:#fff;
    class ST,AM,SA,SH,RD,FI inst;
```

> 🟪 Purple screens are instructor-only. The server enforces this on every
> `/admin/*` route; hiding the button is only cosmetic.

## 2. Sign-in and session

```mermaid
flowchart TD
    A([Open rpl.ponkoj.com/app]) --> B{Saved session token?}
    B -- no --> LOGIN[Login page]
    B -- yes --> C[GET /auth/me]
    C -- valid --> R[Restore progress<br/>GET /me/assignment-progress]
    C -- 401 expired --> X[Dialog: Please sign in again] --> LOGIN
    R --> HOME[Home]

    LOGIN -->|POST /auth/login| HOME
    LOGIN -->|POST /auth/demo| DEMO[Demo session<br/>memory only] --> HOME

    HOME -. any request returns 401 .-> X
```

| Rule | Behaviour |
|---|---|
| Session length | 12 hours (`AUTH_SESSION_HOURS`) |
| Expired mid-work | A dialog appears once, then the app returns to login. Local drafts are kept |
| Demo refresh | Returns to login and wipes all demo state |
| Logout | Revokes the server session and stops research tracking |

## 3. Core student loop: solve an assignment

This is the most important flow in the product.

```mermaid
sequenceDiagram
    autonumber
    actor S as Student
    participant UI as Workspace (Flutter)
    participant API as FastAPI
    participant G as Grader
    participant SB as Sandbox (Docker)
    participant DB as PostgreSQL

    S->>UI: Open assignment
    UI->>API: GET /assignments/{id}
    API-->>UI: instructions, starter code, version (no hidden tests)
    UI->>API: GET /assignments/{id}/draft
    API-->>UI: draft for this exact version (if any)

    loop Edit → run → read feedback
        S->>UI: Type code (autosaves)
        UI->>API: PUT /assignments/{id}/draft
        S->>UI: Run tests
        UI->>API: POST /assignments/{id}/run
        API->>G: grade(code, version)
        G->>SB: execute in isolation (time-limited)
        SB-->>G: return values / errors
        G-->>API: checks, score, evidence
        API->>DB: save Submission (+ version)
        API-->>UI: results + terminal lines
        UI-->>S: Results panel + terminal
    end

    opt Stuck
        S->>UI: Get a hint (levels 1–4)
        UI->>API: POST /assignments/{id}/hint
        API-->>UI: built-in hint (AI only if enabled)
    end
    opt After at least one attempt
        S->>UI: Show solution approach
        UI->>API: POST /assignments/{id}/solution
        API-->>UI: solution explanation
    end
```

### Workspace actions at a glance

| Action | API | Graded? | Saved? |
|---|---|---|---|
| **Run tests** | `POST /assignments/{id}/run` | ✅ | ✅ Submission row |
| **Submit** | `POST /assignments/{id}/submit` | ✅ | ✅ Submission row |
| **Try inputs** | `POST /assignments/{id}/playground` | ❌ | ❌ |
| **Format Python** | `POST /assignments/{id}/format` | ❌ | ❌ |
| **Save draft** (auto) | `PUT /assignments/{id}/draft` | ❌ | ✅ CodeDraft row |
| **Get a hint** | `POST /assignments/{id}/hint` | ❌ | ✅ HintInteraction row (needs an earlier run) |
| **Show solution** | `POST /assignments/{id}/solution` | ❌ | ✅ research event (needs an earlier run) |

> Demo sessions get the same responses, but none of the ✅ rows are written.

### When the assignment version changes

```mermaid
flowchart LR
    A[Student has a draft for v16] --> B[Assignment is updated to v17]
    B --> C[Student opens the assignment]
    C --> D[Workspace loads v17 starter code]
    C --> E[Banner: Your code from an earlier version<br/>View and copy · Dismiss]
```

The older draft is never loaded into the newer workspace automatically.

## 4. Course contents and quiz

```mermaid
flowchart LR
    T[Contents tab<br/>6 topics] --> TP[Topic page<br/>lesson · exercises · math]
    TP --> SEC[Section reader]
    TP --> Q[Topic quiz]
    Q -->|POST /contents/topic/quiz/submit| GR[Server grades the whole quiz]
    GR --> RES[Score + per-question review]
    GR -->|real student only| DB[(CourseQuizAttempt<br/>with quiz version)]
```

The answer keys stay in `backend/course_content/quiz_answers.json`. Demo and
instructor previews are not stored.

## 5. Instructor flows

```mermaid
flowchart TD
    subgraph Assignments
        A1[Create or edit] --> A2[Validate<br/>required fields + grader configuration] --> A3{Valid?}
        A3 -- yes --> A4[Publish<br/>status: draft → published]
        A3 -- no --> A1
    end
    subgraph Accounts
        B1[Add student / instructor] --> B2[Instructor shares the password<br/>student can change it in My account]
        B3[Import accounts file] --> B2
        B4[Deactivate / reset password]
    end
    subgraph Research
        C1[Classroom overview] --> C2[Participant detail<br/>by participant code]
        C1 --> C3[Export dataset .xlsx<br/>no source code, no login IDs]
    end
    subgraph Feedback
        D1[Feedback inbox] --> D2[Mark resolved]
    end
```

## 6. Demo flow (public visitors)

```mermaid
flowchart LR
    V([Visitor]) --> D[Try the student demo] --> S[Server issues a temporary<br/>student session]
    S --> U[Use any student feature]
    U -->|refresh / close tab| GONE[Everything is discarded]
```

The demo writes **no** auth, submission, hint, audit, quiz or research rows.
Each browser's demo is isolated from every other session.
