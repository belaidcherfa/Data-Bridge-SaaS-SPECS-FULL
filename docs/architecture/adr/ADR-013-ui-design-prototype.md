# ADR-013 — Independent UI design prototype

Status: ACCEPTED for the design phase, 2026-09-26. Owner: UX / Frontend / Product.

## Context

After completion of the engineering specification, the user explicitly requested detailed ASCII page designs and a clean React mockup inspired only by the visual identity/components of `belaidcherfa/snowbridge-finops-mvp`. This is a new bounded authorization; the original production implementation gates remain in force.

## Decision

Keep detailed screen specifications in `docs/21-ui-ux` and the independent application in `prototypes/finops-react`. Use React/TypeScript, Vite, local CSS tokens, accessible Radix dialog primitives, TanStack Query/Table and Recharts, with pinned dependencies. The local presentation components follow the intended shadcn-style primitive composition; production shadcn adoption remains part of the original foundation task. Do not import the reference application's Base44 backend, SDK, customer data, business logic, navigation or authentication.

Use one synthetic page catalog plus labelled financial fixtures. Integer-cent arithmetic preserves the main ledger and allocation invariants. Hash routes support local/static preview without backend rewrites. Route scopes are explicit: selectable organization/account for cost overview pages, pinned fixture scopes for entities, budgets and savings studies. Every unavailable telemetry field remains unavailable.

## Alternatives

- Refactor/copy the reference application: rejected because the user explicitly requested a new clean folder and only visual inspiration.
- Implement the production FastAPI/auth/data services alongside the mockup: outside the current authorization and would imply unproven security/data behavior.
- Produce only ASCII documentation: does not satisfy the requested React preview.
- Generate screenshots without executable shared components: insufficient to review navigation, states, forms and financial explanations.

## Consequences

The prototype can prove rendering, component interaction and synthetic arithmetic; it cannot prove tenant isolation, real WIF, historical synchronization, actual financial close, notification delivery or payment. Local draft persistence is clearly labelled. No original production task is marked done solely because this application exists. Production integration must preserve canonical API/security/financial contracts and replace all synthetic adapters.

## Revisit conditions

Revisit when production frontend implementation is authorized, the API contracts are executable, identity/authorization is validated, or user research changes the information architecture. Review dependency versions and the production component choice under FND-002; do not infer a migration requirement from the prototype alone.
