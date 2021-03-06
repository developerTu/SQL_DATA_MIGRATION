

--start--

use usda_foods_sr28_transfer_3_190; --records go into this DB, subject to change depends on the environment 

---------------------------------1.insert food table ---------------------------------

create table food_ready
(
count_id bigint Primary Key IDENTITY(1,1),
description  varchar(255), 
food_group_id bigint, 
last_updated datetime, 
last_updated_by varchar(50),
scientific_name varchar(100),
ndb_no varchar(40)
);

INSERT INTO food_ready (description,  food_group_id, last_updated, last_updated_by, scientific_name, ndb_no)
SELECT
LONG_Desc as  description ,
fg.id as  food_group_id,
'1900-01-01' as last_updated,--last_updated_date is set as '1900-01-01'
'IMPORTED' as last_updated_by,--use 'IMPORT' for last_updated_by
SciName,
NDB_NO
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_group fg on fg.code = fd.FdGrp_Cd
;

--5.3 create a temporal table for assign autal id depending on the count_id (the auto-incremented id)
create table food_makeid
(actual_id BIGINT, count_id bigint );

--5.4 generating the autal id
--8790 row
insert into food_makeid
select
NEXT VALUE FOR food_seq OVER (ORDER BY count_id ) AS actual_id, 
count_id
FROM food_ready;


INSERT INTO food (id , description,  food_group_id, last_updated, last_updated_by, scientific_name)
select 
 mk.actual_id, 
 description,  food_group_id, last_updated, last_updated_by, scientific_name
from food_ready fr
join food_makeid mk on mk.count_id = fr.count_id;



create view food_ndbo_id AS
select 
id, f.description,f.food_group_id,f.last_updated,f.last_updated_by,f.scientific_name, FM.count_id,FM.actual_id, ndb_no
from food f
join food_makeid fm on fm.actual_id = f.id
join food_ready fr on fr.count_id = fm.count_id;


------------------end of 1.insert food table----------------------------------


------------------2. insert food_attribute table------------------------------

--2.1 insert food_attribute table with associated fileds
--1107 rows
Insert into food_attribute(id, food_id, food_attribute_type_id, value, last_updated_by, last_updated)    
select 
NEXT VALUE FOR food_attribute_seq OVER (ORDER BY fni.actual_id) AS id,       
  fni.actual_id  food_id,
'1000' as food_attribute_type_id,--set the id as '1000'                                  
 FD.ComName AS value,
'IMPORTED' as last_updated_by--we assumed te last_updated_by is "IMPORTED" for all records
,'1900-01-01' as last_updated--last_updated_date is set as '1900-01-01'
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_ndbo_id fni on fni.ndb_no = fd.NDB_No
and FD.ComName is NOT NULL;

----------------2. end of insert food_attribute table-------------------------


----------------3. insert final_food table-----------------------------------
--3.1 insert final_food table with associated fileds
--8790
INSERT INTO final_food (food_id, NDB_number)  
SELECT 
fni.actual_id AS food_id
,fni.ndb_no AS NDB_numbers
from  food_ndbo_id fni;

---------------3. end of insert final_food table-------------------------



-------------4. insert final_food_nutrient_conversion and its sbling conversion factor tables---

--4.1 create a table to hold all the conversion factors regardless its parent table, so I will be able to assign conversion_factor_id to each of the conversion factors
CREATE table nutrient_conversion (
ncid BIGINT  NOT NULL IDENTITY (1, 1) PRIMARY KEY ,
actual_id bigint ,
N_FACTOR varchar(255),
--LIPID_CONVERSION_FACTOR varchar(255),--Do NOT have this inforamtion in FOOD_DES(ACCESS) table.
PRO_FACTOR varchar (255),
FAT_FACTOR varchar(255),
CHO_FACTOR varchar(255),
count_id bigint);


--4.2 insert the N_Factor to our temporal table and let it received auto-incremented id.
--6466 rows
   
insert into nutrient_conversion  (actual_id, N_FACTOR, count_id )
select 
fni.actual_id,
N_Factor,
fni.count_id
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_ndbo_id fni on fni.ndb_no = fd.NDB_No
WHERE  N_Factor is not null ;


--4.3 from the auto-incremented id, the  N_Facto gets a real seq id,
--also keep track of where the seq begins and where it will end (set up a temproal value to store the current seq value)
--6466 rows affects, not final(final will be 20508 rows in all)
insert into final_food_nutrient_conversion_factor (id, final_food_id, last_updated,last_updated_by)
SELECT 
NEXT VALUE FOR nutrient_conversion_factor_seq OVER (ORDER BY nc.ncid ),
nc.actual_id,
'1900-01-01'as  last_updated,  --set 1900-01-01 as last updated
'IMPORTED' --IMPORTED (last_updated by)
from nutrient_conversion nc ;

insert into final_food_protein_conversion_factor( final_food_nutrient_conversion_factor_id ,value) --6466 rows
SELECT ffncf.id, N_FACTOR
FROM  nutrient_conversion nc
join  final_food_nutrient_conversion_factor  ffncf on ffncf.final_food_id = nc.actual_id;



--4.4 same method as 4.2 for PRO_CAL_FACTOR
--4591 rows
--DECLARE @ncf_value int ;
--SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'food_seq');   
insert into nutrient_conversion  (actual_id, PRO_FACTOR, count_id )  
select 
fni.actual_id,
FD.Pro_Factor,
fni.count_id
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_ndbo_id fni on fni.ndb_no = fd.NDB_No 
where FD.Pro_Factor is not null;
--WHERE (fni.actual_id > (@ncf_value - 8790) and fni.actual_id <= @ncf_value) and Pro_Factor is not null ;   

--4.5 same method as 4.3 for PRO_CAL_FACTOR
--4591 rows
insert into final_food_nutrient_conversion_factor (id, final_food_id, last_updated,last_updated_by)
SELECT 
NEXT VALUE FOR nutrient_conversion_factor_seq OVER (ORDER BY nc.actual_id ),
nc.actual_id as final_food_id,
'1900-01-01'as  last_updated,  --set 1900-01-01 as last updated
'IMPORTED' --IMPORTED (last_updated by)
from nutrient_conversion nc   
WHERE nc.ncid >6466 ;

DECLARE @ncf_value int ;
SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'nutrient_conversion_factor_seq');  
insert into final_food_calorie_conversion_factor (final_food_nutrient_conversion_factor_id, protein_value)
SELECT ffncf.id, PRO_FACTOR
FROM  nutrient_conversion nc
join  final_food_nutrient_conversion_factor  ffncf on ffncf.final_food_id = nc.actual_id
where (ffncf.id > (@ncf_value-4591)  and ffncf.id <= @ncf_value AND nc.ncid > 6466) ;



--4.6 same method as 4.2 for FAT_CAL_FACTOR
--4689 rows
insert into nutrient_conversion  (actual_id, FAT_FACTOR, count_id )  
select 
fni.actual_id,
FD.Fat_Factor
,fni.count_id
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_ndbo_id fni on fni.ndb_no = fd.NDB_No 
where FD.Fat_Factor is not null;


--4.7 same method as 4.3 for FAT_CAL_FACTOR
--4689 rows
insert into final_food_nutrient_conversion_factor (id, final_food_id, last_updated,last_updated_by)
SELECT 
NEXT VALUE FOR nutrient_conversion_factor_seq OVER (ORDER BY nc.actual_id ),
nc.actual_id as final_food_id,
'1900-01-01'as  last_updated,  --set 1900-01-01 as last updated
'IMPORTED' --IMPORTED (last_updated by)
from nutrient_conversion nc   
WHERE nc.ncid >11057 ;

DECLARE @ncf_value int ;
SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'nutrient_conversion_factor_seq');  
insert into final_food_calorie_conversion_factor (final_food_nutrient_conversion_factor_id, fat_value)
SELECT ffncf.id, fat_FACTOR
FROM  nutrient_conversion nc
join  final_food_nutrient_conversion_factor  ffncf on ffncf.final_food_id = nc.actual_id
where (ffncf.id > (@ncf_value-4689)  and ffncf.id <= @ncf_value AND nc.ncid > 11057) ;


--4.8 same method as 4.2 for CARBOHYDRATE_CAL_FACTOR
--4584 rows
insert into nutrient_conversion  (actual_id, CHO_FACTOR, count_id )  
select 
fni.actual_id,
FD.CHO_Factor
,fni.count_id
from  SR28_TRANSFER.DBO.FOOD_DES FD
join food_ndbo_id fni on fni.ndb_no = fd.NDB_No 
where FD.cho_Factor is not null;


--4.9 same method as 4.3 for CARBOHYDRATE_CAL_FACTOR
--4584 rows
insert into final_food_nutrient_conversion_factor (id, final_food_id, last_updated,last_updated_by)
SELECT 
NEXT VALUE FOR nutrient_conversion_factor_seq OVER (ORDER BY nc.actual_id ),
nc.actual_id as final_food_id,
'1900-01-01'as  last_updated,  --set 1900-01-01 as last updated
'IMPORTED' --IMPORTED (last_updated by)
from nutrient_conversion nc   
WHERE nc.ncid >15746 ;

DECLARE @ncf_value int ;
SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'nutrient_conversion_factor_seq');  
insert into final_food_calorie_conversion_factor (final_food_nutrient_conversion_factor_id, carbohydrate_value)
SELECT ffncf.id, CHO_FACTOR
FROM  nutrient_conversion nc
join  final_food_nutrient_conversion_factor  ffncf on ffncf.final_food_id = nc.actual_id
where (ffncf.id > (@ncf_value-4584)  and ffncf.id <= @ncf_value AND nc.ncid > 15746) ;

-------------4. end of insert final_food_nutrient_conversion and its sbling conversion factor tables---




---------------------------------------5. insert food_nutrient ------------------------------------------------------------------------
--5.1 create a temporal table to hold food_nutrient fileds and create(assign) id for each records from Access (those records in Access use composite PK, but we need a single PK)
--679238 row
create table food_nutrient_ready
(
count_id bigint Primary Key IDENTITY(1,1),
food_id bigint, 
nutrient_id bigint, 
data_points int, 
standard_error decimal(19, 8),
derivation_id bigint,
last_updated datetime, 
value decimal(19, 8),
min decimal(19, 8),
max decimal(19, 8),
degrees_of_freedom decimal(19, 8),
median decimal(19, 8)
);


--5.2 insert food_nutrient to the table just created to receive auto_incremented id with all the other fields
---679238 rows
DECLARE @ncf_value int ;
SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'food_seq');  
INSERT INTO food_nutrient_ready  (food_id, nutrient_id, data_points, standard_error,derivation_id, last_updated, value, min, max, degrees_of_freedom)
select   
fni.actual_id as food_id,
n.id as nutrient_id, 
ND.Num_Data_Pts as data_points,
ND.Std_Error as standard_error,
d.id as derivation_id,
(case 
when  nd.[ADDMOD_DATE] is null  then CAST('01/01/1900' AS DATETIME)                              --set date '1900/01/01' if null
else CAST((SUBSTRING(nd.[ADDMOD_DATE],1,2) + '/01' + SUBSTRING(nd.[ADDMOD_DATE],3,5)) as datetime)--set date '01/MM/YYYY' 
end) as last_updated,
 ND.Nutr_Val as value,
 ND.Min as min,
 ND.Max as max,
 ND.DF  as degrees_of_freedom
FROM sr28_transfer.dbo.NUT_DATA ND
jOIN food_ndbo_id fni on fni.ndb_no = nd.NDB_No
JOIN nutrient n on n.nutrient_nbr = ND.Nutr_No
LEFT JOIN [food_nutrient_derivation] D ON D.code = ND.Deriv_Cd
Where  (fni.actual_id > (@ncf_value - 8790) and fni.actual_id <= @ncf_value)  ORDER BY ND.NDB_No;

--5.3 create a temporal table for assign autal id depending on the count_id (the auto-incremented id)
create table food_nutrient_makeid
(actual_id BIGINT, count_id bigint );

--5.4 generating the autal id
--679238 rows
insert into food_nutrient_makeid
select
NEXT VALUE FOR food_nutrient_seq OVER (ORDER BY count_id ) AS actual_id, 
count_id
FROM food_nutrient_ready;

--5.5 insert food_nutrient table with all the filds plus the actual ids 
--679238 rows
INSERT INTO food_nutrient  (id, food_id, nutrient_id, data_points, standard_error,derivation_id, last_updated, value, last_updated_by, min, max, degrees_of_freedom)
SELECT
actual_id , food_id, nutrient_id, data_points, standard_error,derivation_id, last_updated, value, 'IMPORTED' as last_updated_by, min, max, degrees_of_freedom
FROM food_nutrient_ready fnr
join  food_nutrient_makeid fnm on fnm.count_id = fnr.count_id;
-----------------end of insert food_nutrient------------------------------------------
 

----------------6. begin of insert lab_analysis_sub_sample_results------------

--6.1 Insert into lab_analysis_sub_sample_results with mappable fields
--grab the current fn_seq value, and only transfer the targeted 679238 rows   where id= (current_seq_value -679238 rows,  current_seq_value]
--679238 rows
 DECLARE @fnr_value int ;   
 SET @fnr_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'food_nutrient_seq');    
 Insert into lab_analysis_sub_sample_result (food_nutrient_id, nutrient_name,  unit)
 select  
 fn.id as food_nutrient_id,
 convert(varchar(50), NF.NutrDesc )as nutrient_name,
 NF.UNITS AS unit
 FROM sr28_transfer.dbo.NUTR_DEF NF
 join sr28_transfer.dbo.NUT_DATA ND ON ND.Nutr_No = NF.Nutr_No
 JOIN nutrient n on n.nutrient_nbr = ND.Nutr_No
 JOIN food_ndbo_id fni on fni.ndb_no = nd.NDB_No
 JOIN food_nutrient fn on fn.food_id = fni.actual_id and fn.nutrient_id = n.id
 WHERE  (fn.id > (@fnr_value -679238) and fn.id <= @fnr_value );
 ---------------- end of 6. insert lab_analysis_sub_sample_results------------



-----------------------------------------7. insert food measure table-------------------------------------------- 
--7.1 clean the unit names, get rid of any "," and "."
--15439 rows
CREATE VIEW  measure_unit_modify_3_1_1 AS
SELECT 
NDB_NO ,Seq, Amount 
,CASE WHEN W.Msre_Desc LIKE '%,' THEN LEFT(W.Msre_Desc, LEN(W.Msre_Desc)-1) 
WHEN W.Msre_Desc LIKE '%.' THEN LEFT(W.Msre_Desc, LEN(W.Msre_Desc)-1)       
ELSE W.Msre_Desc  END AS [UNIT_NAME],
W.Gm_Wgt,
W.Num_Data_Pts,
W.Std_Dev
FROM sr28_transfer.dbo.WEIGHT W;


--7.2 correct unit names with space at the beginning
--15439 rows
CREATE VIEW measure_unit_modify_3_1_2   AS
 SELECT    
     NDB_NO ,Seq, Amount 
      ,LTRIM(RTRIM([UNIT_NAME])) AS [UNIT_NAME],
W.Gm_Wgt,
W.Num_Data_Pts,
W.Std_Dev
FROM measure_unit_modify_3_1_1 w ;


--7.3 add one record into measure_unit for the unmatched record. 
--***************dont add if it already exists
INSERT INTO measure_unit (id, name, abbreviation) VALUES ('9999','undetermined' ,'undetermined');


--7.4 get all unit names in the measure unit table as standard names and the mesure_id
CREATE VIEW  king_of_unit_name_3_1 AS 
SELECT [id]
      ,[name]  AS unit_name
FROM [measure_unit]
UNION
SELECT [id]
      ,[abbreviation] AS unit_name
FROM [measure_unit];



--7.5 create a temporal table to hold food_measure filed and create(assign) id for each records from Access (those records in Access use composite PK, but we need a single PK)
create table food_measure_ready
(
count_id bigint Primary Key IDENTITY(1,1),
food_id bigint, 
value decimal(19, 8),
gram_weight decimal(19, 8),
data_points int,
measure_unit_id BIGINT,
standard_error decimal(19, 8)
);

--7.6 insert food_measure to the table just created to receive auto_incremented id with all the other fields
--15439 rows
DECLARE @ncf_value int ;
SET @ncf_value = (SELECT convert(int, current_value) FROM sys.sequences WHERE name = 'food_seq');  
insert into food_measure_ready (food_id, value, gram_weight, data_points, measure_unit_id, standard_error)
SELECT 
 FNI.actual_id as food_id,
MUM2.AMOUNT AS value,
 MUM2.Gm_Wgt as [gram_weight] ,
 MUM2.Num_Data_Pts as data_points ,
 IIF (koun.id is NULL, '9999', koun.id) as measure_unit_id,                   --assign id'9999' to the unmatched units
 MUM2.Std_Dev AS standard_error
 FROM measure_unit_modify_3_1_2 mum2
 left join king_of_unit_name_3_1 koun  ON koun.[unit_name] = mum2.[UNIT_NAME]
 join SR28_TRANSFER.DBO.FOOD_DES FD on fd.NDB_No = mum2.NDB_No
 join food_ndbo_id fni on fni.ndb_no = mum2.NDB_No
 Where  (FNI.actual_id > (@ncf_value - 8790) and FNI.actual_id<= @ncf_value) ;

--7.7 create a temporal table for assign autal id depending on the count_id (the auto-incremented id)
--15439 rows
 create table food_measure_makeid
(actual_id BIGINT, count_id bigint );


insert into food_measure_makeid
select
NEXT VALUE FOR food_measure_seq OVER (ORDER BY count_id ) AS actual_id, 
count_id
FROM food_measure_ready;


--7.8 insert food_measure table with all the filds plus the  actual id from the seq
--15439 rows
INSERT INTO food_measure (id, food_id,  value, gram_weight, data_points, measure_unit_id, standard_error, last_updated, last_updated_by)
SELECT
actual_id , food_id, 
value,
gram_weight,
data_points,
measure_unit_id,
standard_error,
'1900-01-01' as last_updated,    -- Not such a column in WEIGHT(ACCESS) table. using a fake date
'IMPORTED' --IMPORTED (last_updated by)
FROM food_measure_ready fnr
join  food_measure_makeid fnm on fnm.count_id = fnr.count_id;
------------------------------end of insert food measure-----------------------



--drop the temporal tables and views
drop table food_ready;
drop table food_makeid;
drop table nutrient_conversion;
drop table food_nutrient_ready;
drop table food_nutrient_makeid;
drop table food_measure_ready;
drop table food_measure_makeid;

drop view food_ndbo_id;
drop view measure_unit_modify_3_1_1;
drop view measure_unit_modify_3_1_2;
drop view king_of_unit_name_3_1;
--done--