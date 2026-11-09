-- LIGA DEL ROCÓDROMO · Supabase
-- 1) El administrador es eskalibur@gmail.com (función liga_is_owner, más abajo).
-- 2) Pega todo este archivo en Supabase > SQL Editor y pulsa Run.
-- Todas las tablas empiezan por liga_, así que puede ir en el mismo proyecto que «Mis vías» sin pisarse.

-- Escaladores: el nombre que sale en el ranking
create table liga_players(
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  name text not null unique check (char_length(name) between 2 and 30),
  created_at timestamptz default now());

-- Vías de cuerda y autoseguro (con línea) y bloques de boulder (con sector).
-- En boulder, "grade" guarda el color de dificultad (blanco, verde... dorado).
create table liga_routes(
  id uuid primary key default gen_random_uuid(),
  sec text not null check (sec in ('cuerda','autoseguro','boulder')),
  line int,
  zone text,
  grade text not null,
  hold text,
  created date default current_date,
  active boolean not null default true,
  check ((sec = 'boulder' and zone is not null) or (sec <> 'boulder' and line is not null)));

-- Puntos por grado (vías) y por color (bloques), y multiplicadores por estilo.
-- Puedes cambiarlos cuando quieras desde Table Editor: la app los lee al abrirse.
create table liga_points(
  kind text not null check (kind in ('via','bloque')),
  grade text not null,
  pts int not null,
  primary key(kind, grade));
create table liga_styles(
  kind text not null check (kind in ('via','bloque')),
  style text not null,
  mult numeric not null,
  primary key(kind, style));

insert into liga_points values
 ('via','4',30),('via','5',50),('via','5+',70),('via','6a',100),('via','6a+',120),('via','6b',150),('via','6b+',180),
 ('via','6c',220),('via','6c+',260),('via','7a',320),('via','7a+',380),('via','7b',450),('via','7b+',520),('via','7c',600),
 ('via','7c+',700),('via','8a',800),
 ('bloque','blanco',20),('bloque','verde',40),('bloque','amarillo',70),('bloque','azul',110),('bloque','morado',160),
 ('bloque','rojo',230),('bloque','negro',320),('bloque','dorado',450);
insert into liga_styles values
 ('via','A vista',1.3),('via','Flash',1.15),('via','Encadenada',1),
 ('bloque','Flash',1.2),('bloque','Encadenado',1);

-- Encadenes: una vez por vía y bimestre para cada escalador
create table liga_ascents(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  route_id uuid not null references liga_routes(id) on delete cascade,
  sec text,
  grade text,
  style text not null,
  bim text,
  done_at timestamptz not null default now(),
  unique(user_id, route_id, bim));
create index on liga_ascents(done_at);

-- Antitrampas: la base de datos pone la fecha, el escalador, la sección, el grado y el bimestre.
-- Nadie puede poner encadenes con fecha atrasada ni cambiar el grado de una vía.
create function liga_ascent_fill() returns trigger language plpgsql security definer set search_path = public as $$
declare r liga_routes%rowtype; k text;
begin
  select * into r from liga_routes where id = new.route_id;
  if not found or not r.active then raise exception 'Esa vía ya no está montada'; end if;
  k := case r.sec when 'boulder' then 'bloque' else 'via' end;
  if not exists (select 1 from liga_styles where kind = k and style = new.style) then raise exception 'Estilo no válido'; end if;
  if tg_op = 'INSERT' then
    new.done_at := now(); new.user_id := auth.uid();
  else
    new.done_at := old.done_at; new.user_id := old.user_id; new.route_id := old.route_id;
  end if;
  new.sec := r.sec; new.grade := r.grade;
  new.bim := to_char(new.done_at at time zone 'Europe/Madrid', 'YYYY') || '-' ||
             ((extract(month from new.done_at at time zone 'Europe/Madrid')::int - 1) / 2);
  return new;
end $$;
create trigger liga_ascent_fill before insert or update on liga_ascents
  for each row execute function liga_ascent_fill();

-- Administrador: solo tú montas, corriges y desmontas vías y bloques
create function liga_is_owner() returns boolean language sql stable as
$$ select coalesce(auth.jwt()->>'email', '') = 'eskalibur@gmail.com' $$;

do $$ declare t text; begin
  foreach t in array array['liga_routes','liga_points','liga_styles'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "leer" on %I for select using (true)', t);
    execute format('create policy "admin" on %I for all using (liga_is_owner()) with check (liga_is_owner())', t);
  end loop;
end $$;

-- Todos ven a todos; cada uno solo crea y cambia lo suyo
alter table liga_players enable row level security;
create policy "ver escaladores" on liga_players for select using (true);
create policy "crear mi nombre" on liga_players for insert with check (auth.uid() = user_id);
create policy "cambiar mi nombre" on liga_players for update using (auth.uid() = user_id);

alter table liga_ascents enable row level security;
create policy "ver encadenes" on liga_ascents for select using (true);
create policy "marcar los mios" on liga_ascents for insert with check (auth.uid() = user_id);
create policy "cambiar los mios" on liga_ascents for update using (auth.uid() = user_id);
create policy "quitar los mios" on liga_ascents for delete using (auth.uid() = user_id);

-- Tiempo real: los rankings se actualizan solos en todos los móviles
alter publication supabase_realtime add table liga_ascents, liga_routes, liga_players;
