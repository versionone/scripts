-- Are there any schema-unqualified names in our DDL?
select OBJECT_NAME(referencing_id) ReferencingEntity, referenced_entity_name UnqualifiedReferencedName, * 
from sys.sql_expression_dependencies 
where 
	referenced_schema_name is null 
	or is_caller_dependent=1 
	or is_ambiguous=1