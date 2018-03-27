# Development Notes

### Reactive Programming

* In SPs that have no value, always send an empty tuple as a value. Otherwise, any observer listening for a result will never be triggered.

### Notebook editor

* not using invalidationcontext because should never be enough chunks that resizing should cause a performance issue


notebook saving

* should we save invalid syntax?
* should we cache results?
* autosave?
* are we storing everything necessary for reproduction?

clear undo cache on file change notification from server


### code templates

create table if not exists TemplateCategory (
  category_id integer primary key,
  category_name text not null
);

create table if not exists Template (
  template_id integer primary key,
  category_id integer not null,
  order_id integer not null default 1,
  name text not null,
  contents text not null,
  foreign key (category_id) references TemplateCategory(category_id) on delete restrict
);

insert into TemplateCategory (rowid, category_name) values (1, 'Markdown');
insert into TemplateCategory (rowid, category_name) values (2, 'R Code');
insert into TemplateCategory (rowid, category_name) values (3, 'Equations');

insert into Template(category_id, name, contents) values (3, 'Pythagorean equation', 'a^2 + b^2 = c^2');
insert into Template(category_id, name, contents) values (3, 'sqrt 2', '\sqrt{2}');
insert into Template(category_id, name, contents) values (1, '2nd header', '## header');
insert into Template(category_id, name, contents) values (2, 'basic array', 'yar <- c(1,3,45)');
