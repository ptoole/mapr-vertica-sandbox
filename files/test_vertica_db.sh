#!/bin/bash

DBADMIN=dbadmin
ADMINTOOLS="sudo -u $DBADMIN /opt/vertica/bin/admintools"
VSQL="sudo -u $DBADMIN /opt/vertica/bin/vsql"

$VSQL -c "drop table if exists test; create table test(a int);"
echo -e "1\n2\n3\n4\n.\n" | $VSQL -c "copy test from stdin;"

rc=$($VSQL -c "select * from test;" | wc -l)

# Should see 
#    a 
#   ---
#    1
#    2
#    3
#    4
#   (4 rows)
#   
# 8 lines total (including trailing blank) ... 4 data rows plus 4 extra

echo "$[rc-4] rows retrieved"
if [ $rc -eq 8 ]; then echo Passed; else echo Failed; fi

