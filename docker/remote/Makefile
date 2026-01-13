LOG_PERIOD ?= 5m
DEFAULT_COMMAND = /bin/bash
DB_DUMP_CMD = /app/bin/db_dump

.DEFAULT_GOAL := exec_qa_web

define exec
	${shell ENVIRONMENT=$(1) APPLICATION=${2} ecs_helper exec -c=$(3) --command="${4}"}
endef

define logs
	awslogs get ${1} ALL --start ${LOG_PERIOD}
endef

define watch_logs
	awslogs get ${1} ALL --watch
endef

define dump_db
	aws s3 cp s3://${1}/db_dumps/latest.sql.gz db_dumps/latest.sql.gz
endef

exec_qa_web:
	${call exec,qa,app-web,web,"${DEFAULT_COMMAND}"}

qa_web_logs:
	${call logs,palad-qa-app-web}

watch_qa_web_logs:
	${call watch_logs,palad-qa-app-web}

exec_prod_web:
	${call exec,prod,app-web,web,"${DEFAULT_COMMAND}"}

prod_web_logs:
	${call logs,palad-prod-app-web}

watch_prod_web_logs:
	${call logs,palad-prod-app-web}

dump_qa:
	${call exec,qa,app-web,web,"${DB_DUMP_CMD}"}

dump_prod:
	${call exec,prod,app-web,web,"${DB_DUMP_CMD}"}

fetch_qa_dump:
	${call dump_db,palad-qa-app}

fetch_prod_dump:
	${call dump_db,palad-prod-app}
