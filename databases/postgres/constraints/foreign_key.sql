
create table people(no varchar2(10), 
                     fname varchar2(20), 
                     foreign key(no) references person(id));

--ON DELETE CASCADE : When this option is specified in foreign key definition, if a record is deleted in master table, all corresponding record in detail table will be deleted.
create table people(no varchar2(10), 
                   fname varchar2(20), 
                   foreign key(no) references person on delete cascade);

--ON DELETE SET NULL : means if record in parent table is deleted, corresponding records in child table will have foreign key fields set to null. Records in child table will not be deleted.
create table people(no varchar2(10), 
                 fname varchar2(20), 
                    foreign key(no) references person on delete set null);

