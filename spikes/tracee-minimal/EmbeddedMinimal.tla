---------------------------- MODULE EmbeddedMinimal ----------------------------
EXTENDS Integers

VARIABLES
  \* @type: Int;
  count,
  \* @type: Int;
  expectedDouble

Init == /\ count = 0
        /\ expectedDouble = 0

Next == /\ count < 2
        /\ count' = count + 1
        /\ expectedDouble' = 2 * (count + 1)

Spec == Init /\ [][Next]_<<count, expectedDouble>>
=============================================================================