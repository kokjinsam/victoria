---------------------------- MODULE TraceeMinimal ----------------------------
EXTENDS Integers

VARIABLE
  \* @type: Int;
  count

Init == count = 0
Next == /\ count < 2
        /\ count' = count + 1

\* Pure projection: not carried as a second state variable.
Double == 2 * count

Spec == Init /\ [][Next]_count
=============================================================================