--------------------------- MODULE IdenticalProjects ---------------------------
EXTENDS Integers

VARIABLES
  \* @type: Int;
  step,
  \* @type: Str;
  firstSymbol,
  \* @type: Str;
  secondSymbol,
  \* @type: Bool;
  createdFirst,
  \* @type: Bool;
  createdSecond,
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

InitCommon ==
  /\ step = 0
  /\ firstSymbol # secondSymbol
  /\ createdFirst = FALSE
  /\ createdSecond = FALSE
  /\ operationId = "Initial"
  /\ actor = "none"
  /\ requestBody = [name |-> ""]
  /\ expectedStatus = 0
  /\ expectedBody = [name |-> ""]
  /\ checkBody = FALSE
  /\ bindResource = FALSE
  /\ checkIdentity = FALSE
  /\ resourceSymbol = firstSymbol

InitAlpha ==
  /\ firstSymbol = "projectA"
  /\ secondSymbol = "projectB"
  /\ InitCommon

InitBeta ==
  /\ firstSymbol = "projectB"
  /\ secondSymbol = "projectA"
  /\ InitCommon

KeepOrder ==
  /\ UNCHANGED <<firstSymbol, secondSymbol>>

CreateFirst ==
  /\ step = 0
  /\ step' = 1
  /\ createdFirst' = TRUE
  /\ createdSecond' = FALSE
  /\ KeepOrder
  /\ operationId' = "createProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> "Same"]
  /\ expectedStatus' = 201
  /\ expectedBody' = [name |-> "Same"]
  /\ checkBody' = FALSE
  /\ bindResource' = TRUE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = firstSymbol

CreateSecond ==
  /\ step = 1
  /\ createdFirst
  /\ step' = 2
  /\ createdFirst' = TRUE
  /\ createdSecond' = TRUE
  /\ KeepOrder
  /\ operationId' = "createProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> "Same"]
  /\ expectedStatus' = 201
  /\ expectedBody' = [name |-> "Same"]
  /\ checkBody' = FALSE
  /\ bindResource' = TRUE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = secondSymbol

ReadFirst ==
  /\ step = 2
  /\ createdFirst
  /\ createdSecond
  /\ step' = 3
  /\ UNCHANGED <<createdFirst, createdSecond>>
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> "Same"]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = firstSymbol

ReadSecond ==
  /\ step = 3
  /\ createdFirst
  /\ createdSecond
  /\ step' = 4
  /\ UNCHANGED <<createdFirst, createdSecond>>
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> "Same"]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = secondSymbol

Next == CreateFirst \/ CreateSecond \/ ReadFirst \/ ReadSecond
=============================================================================