------------------------- MODULE IdentityEquivalence -------------------------
EXTENDS Integers
VARIABLES
 \* @type: Int;
 step,
 \* @type: Str;
 mode,
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
 resourceSymbol,
 \* @type: Str;
 identityDomain,
 \* @type: Str;
 identityKey

InitCommon ==
 /\ step = 0
 /\ operationId = "Initial"
 /\ actor = "none"
 /\ requestBody = [name |-> ""]
 /\ expectedStatus = 0
 /\ expectedBody = [name |-> ""]
 /\ checkBody = FALSE
 /\ bindResource = FALSE
 /\ checkIdentity = FALSE
 /\ resourceSymbol = "primary"
 /\ identityDomain = "projects"
 /\ identityKey = "entityA"

InitAlias == InitCommon /\ mode = "alias"
InitDistinct == InitCommon /\ mode = "distinct"

CreatePrimary ==
 /\ step = 0 /\ step' = 1
 /\ UNCHANGED mode
 /\ operationId' = "createProject"
 /\ actor' = "admin"
 /\ requestBody' = [name |-> "Same"]
 /\ expectedStatus' = 201
 /\ expectedBody' = [name |-> "Same"]
 /\ checkBody' = FALSE
 /\ bindResource' = TRUE
 /\ checkIdentity' = FALSE
 /\ resourceSymbol' = "primary"
 /\ identityDomain' = "projects"
 /\ identityKey' = "entityA"

CreateAlternate ==
 /\ step = 1 /\ step' = 2
 /\ UNCHANGED mode
 /\ operationId' = "createReference"
 /\ actor' = "admin"
 /\ requestBody' = [name |-> "Same"]
 /\ expectedStatus' = 201
 /\ expectedBody' = [name |-> "Same"]
 /\ checkBody' = FALSE
 /\ bindResource' = TRUE
 /\ checkIdentity' = FALSE
 /\ resourceSymbol' = "alternate"
 /\ identityDomain' = "projects"
 /\ identityKey' = IF mode = "alias" THEN "entityA" ELSE "entityB"

ReadAlternate ==
 /\ step = 2 /\ step' = 3
 /\ UNCHANGED mode
 /\ operationId' = "getReference"
 /\ actor' = "admin"
 /\ requestBody' = [name |-> ""]
 /\ expectedStatus' = 200
 /\ expectedBody' = [name |-> "Same"]
 /\ checkBody' = TRUE
 /\ bindResource' = FALSE
 /\ checkIdentity' = TRUE
 /\ resourceSymbol' = "alternate"
 /\ identityDomain' = "projects"
 /\ identityKey' = IF mode = "alias" THEN "entityA" ELSE "entityB"

ReadPrimary ==
 /\ step = 3 /\ step' = 4
 /\ UNCHANGED mode
 /\ operationId' = "getProject"
 /\ actor' = "admin"
 /\ requestBody' = [name |-> ""]
 /\ expectedStatus' = 200
 /\ expectedBody' = [name |-> "Same"]
 /\ checkBody' = TRUE
 /\ bindResource' = FALSE
 /\ checkIdentity' = TRUE
 /\ resourceSymbol' = "primary"
 /\ identityDomain' = "projects"
 /\ identityKey' = "entityA"

Next == CreatePrimary \/ CreateAlternate \/ ReadAlternate \/ ReadPrimary
=============================================================================