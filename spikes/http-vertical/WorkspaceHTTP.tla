-------------------------- MODULE WorkspaceHTTP --------------------------
EXTENDS Integers
VARIABLES
  \* @type: Int;
  step,
  \* @type: Bool;
  memberActive,
  \* @type: Int;
  projectCount,
  \* @type: Str;
  operationId,
  \* @type: Str;
  actor,
  \* @type: [name: Str];
  requestBody,
  \* @type: Int;
  expectedStatus,
  \* @type: [count: Int];
  expectedBody,
  \* @type: Bool;
  checkBody

vars == <<step, memberActive, projectCount, operationId, actor,
          requestBody, expectedStatus, expectedBody, checkBody>>

Init ==
  /\ step = 0
  /\ memberActive = TRUE
  /\ projectCount = 0
  /\ operationId = "Initial"
  /\ actor = "none"
  /\ requestBody = [name |-> ""]
  /\ expectedStatus = 0
  /\ expectedBody = [count |-> 0]
  /\ checkBody = FALSE

Deactivate ==
  /\ step = 0
  /\ step' = 1
  /\ memberActive' = FALSE
  /\ projectCount' = projectCount
  /\ operationId' = "deactivateMember"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [count |-> projectCount]
  /\ checkBody' = FALSE

RejectCreate ==
  /\ step = 1
  /\ ~memberActive
  /\ step' = 2
  /\ UNCHANGED <<memberActive, projectCount>>
  /\ operationId' = "createProject"
  /\ actor' = "member"
  /\ requestBody' = [name |-> "Ghost Project"]
  /\ expectedStatus' = 403
  /\ expectedBody' = [count |-> projectCount]
  /\ checkBody' = FALSE

Observe ==
  /\ step = 2
  /\ step' = 3
  /\ UNCHANGED <<memberActive, projectCount>>
  /\ operationId' = "listProjects"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [count |-> projectCount]
  /\ checkBody' = TRUE

Next == Deactivate \/ RejectCreate \/ Observe
VisibleCount == projectCount
Spec == Init /\ [][Next]_vars
=============================================================================