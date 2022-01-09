
select "var bj_globals = /^(?:" || group_concat(fnname, "|") || ")\b/"
from annotations
where anname == 'type' and value == 'global' and fnname like "bj_%";

select "var cj_globals = /^(?:" || group_concat(fnname, "|") || ")\b/"
from annotations
where anname == 'type' and value == 'global' and fnname not like "bj_%";

select "var types = /^(?:" || group_concat(fnname, "|") || ")\b/"
from annotations
where anname == 'type' and value == 'type';

select "var natives = /^(?:" || group_concat(fnname, "|") || ")\b/"
from annotations
where anname == 'type' and value == 'native';

select "var bj = /^(?:" || group_concat(fnname, "|") || ")\b/"
from annotations
where anname == 'type' and value == 'function';
