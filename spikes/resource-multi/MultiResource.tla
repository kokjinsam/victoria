------------------------------ MODULE MultiResource ------------------------------
EXTENDS Integers
VARIABLES
  \* @type: Int;
  step,
  \* @type: Bool;
  existsA,
  \* @type: Bool;
  existsB,
  \* @type: Str;
  firstSymbol,
  \* @type: Str;
  secondSymbol,
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

NameOf(symbol) == IF symbol = "projectA" THEN "Alpha" ELSE "Beta"

InitCommon ==
  /\ step = 0
  /\ existsA = FALSE
  /\ existsB = FALSE
  /\ operationId = "Initial"
  /\ actor = "none"
  /\ requestBody = [name |-> ""]
  /\ expectedStatus = 0
  /\ expectedBody = [name |-> ""]
  /\ checkBody = FALSE
  /\ bindResource = FALSE
  /\ checkIdentity = FALSE
  /\ resourceSymbol = "projectA"

InitAlpha ==
  /\ InitCommon
  /\ firstSymbol = "projectA"
  /\ secondSymbol = "projectB"

InitBeta ==
  /\ InitCommon
  /\ firstSymbol = "projectB"
  /\ secondSymbol = "projectA"

KeepOrder ==
  /\ firstSymbol' = firstSymbol
  /\ secondSymbol' = secondSymbol

CreateFirst ==
  /\ step = 0
  /\ step' = 1
  /\ existsA' = (firstSymbol = "projectA")
  /\ existsB' = (firstSymbol = "projectB")
  /\ KeepOrder
  /\ operationId' = "createProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> NameOf(firstSymbol)]
  /\ expectedStatus' = 201
  /\ expectedBody' = [name |-> NameOf(firstSymbol)]
  /\ checkBody' = FALSE
  /\ bindResource' = TRUE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = firstSymbol

CreateSecond ==
  /\ step = 1
  /\ step' = 2
  /\ existsA' = TRUE
  /\ existsB' = TRUE
  /\ KeepOrder
  /\ operationId' = "createProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> NameOf(secondSymbol)]
  /\ expectedStatus' = 201
  /\ expectedBody' = [name |-> NameOf(secondSymbol)]
  /\ checkBody' = FALSE
  /\ bindResource' = TRUE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = secondSymbol

GetSecond ==
  /\ step = 2
  /\ existsA
  /\ existsB
  /\ step' = 3
  /\ existsA' = existsA
  /\ existsB' = existsB
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> NameOf(secondSymbol)]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = secondSymbol

GetFirst ==
  /\ step = 3
  /\ step' = 4
  /\ existsA' = existsA
  /\ existsB' = existsB
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> NameOf(firstSymbol)]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = firstSymbol

DeleteFirst ==
  /\ step = 4
  /\ step' = 5
  /\ existsA' = (secondSymbol = "projectA")
  /\ existsB' = (secondSymbol = "projectB")
  /\ KeepOrder
  /\ operationId' = "deleteProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> ""]
  /\ checkBody' = FALSE
  /\ bindResource' = FALSE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = firstSymbol

GetSecondAgain ==
  /\ step = 5
  /\ step' = 6
  /\ existsA' = existsA
  /\ existsB' = existsB
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 200
  /\ expectedBody' = [name |-> NameOf(secondSymbol)]
  /\ checkBody' = TRUE
  /\ bindResource' = FALSE
  /\ checkIdentity' = TRUE
  /\ resourceSymbol' = secondSymbol

GetFirstGone ==
  /\ step = 6
  /\ step' = 7
  /\ existsA' = existsA
  /\ existsB' = existsB
  /\ KeepOrder
  /\ operationId' = "getProject"
  /\ actor' = "admin"
  /\ requestBody' = [name |-> ""]
  /\ expectedStatus' = 404
  /\ expectedBody' = [name |-> ""]
  /\ checkBody' = FALSE
  /\ bindResource' = FALSE
  /\ checkIdentity' = FALSE
  /\ resourceSymbol' = firstSymbol

Next ==
  CreateFirst \/ CreateSecond \/ GetSecond \/ GetFirst \/
  DeleteFirst \/ GetSecondAgain \/ GetFirstGone
=============================================================================