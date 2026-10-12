--------------------------- MODULE ResourceLifecycle ---------------------------
EXTENDS Integers

VARIABLES
  \* @type: Int;
  step,
  \* @type: Bool;
  projectExists,
  \* @type: Str;
  operationId,
  \* @type: Str;
  actor,
  \* @type: {name: Str};
  requestBody,
  \* @type: Int;
  expectedStatus,
  \* @type: {name: Str};
  expectedBody,
  \* @type: Bool;
  checkBody,
  \* @type: Bool;
  bindResource,
  \* @type: Bool;
  checkIdentity,
  \* @type: Str;
  resourceSymbol

Init ==
  /\ step = 0
  /\ projectExists = FALSE
  /\ operationId = "Initial"
  /\ actor = "none"
  /\ requestBody = [name |-> ""]
  /\ expectedStatus = 0
  /\ expectedBody = [name |-> ""]
  /\ checkBody = FALSE
  /\ bindResource = FALSE
  /\ checkIdentity = FALSE
  /\ resourceSymbol = "projectA"

Create ==
  /\ step = 0
  /\ step' = 1
  /\ projectExists' = TRUE
  /\ operationId' = "createProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> "Alpha"]
  /\ expectedStatus' = 201
  /\ expectedBody' = [name |-> "Alpha"]
  /\ checkBody' = FALSE
  /\ bindResource' = TRUE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = "projectA"

Retrieve ==
  /\ step = 1
  /\ projectExists
  /\ step' = 2
  /\ UNCHANGED projectExists
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> "Alpha"]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = "projectA"

Delete ==
  /\ step = 2
  /\ projectExists
  /\ step' = 3
  /\ projectExists' = FALSE
  /\ operationId' = "deleteProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> ""]
  /\ checkBody' = FALSE
  /\ bindResource' = FALSE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = "projectA"

CheckDeleted ==
  /\ step = 3
  /\ ~projectExists
  /\ step' = 4
  /\ UNCHANGED projectExists
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 404
  /\ expectedBody' = [name |-> ""]
  /\ checkBody' = FALSE
  /\ bindResource' = FALSE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = "projectA"

Next == Create \/ Retrieve \/ Delete \/ CheckDeleted
=============================================================================