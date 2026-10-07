-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run
-- CHANGE the fare below (v_fare) and the boarding list if needed.

create table if not exists bookings(
  id uuid default gen_random_uuid() primary key,
  ref text unique not null, name text not null, phone text not null,
  boarding text, seats text[] not null, amount int not null, utr text,
  status text not null default 'held' check (status in ('held','pending','confirmed','rejected','expired')),
  expires_at timestamptz, created_at timestamptz default now());

-- one row per locked seat; the PRIMARY KEY makes double booking impossible
create table if not exists seat_locks(
  seat text primary key,
  booking_id uuid references bookings(id) on delete cascade);

alter table bookings enable row level security;
alter table seat_locks enable row level security;
-- customers (anon) get NO direct table access; only the owner (logged in) can read bookings
drop policy if exists owner_read on bookings;
create policy owner_read on bookings for select to authenticated using (true);

create or replace function hold_seats(p_seats text[], p_name text, p_phone text, p_boarding text)
returns json language plpgsql security definer set search_path=public as $$
declare v_fare int := 1299;                      -- price per seat (use 1 for testing)
        v_id uuid; v_ref text; v_exp timestamptz := now() + interval '15 minutes'; s text; n int;
begin
  n := coalesce(array_length(p_seats,1),0);
  if n < 1 or n > 5 then raise exception 'bad_seats'; end if;
  if p_phone !~ '^[6-9][0-9]{9}$' or length(trim(p_name)) not between 2 and 40 then raise exception 'bad_input'; end if;
  if p_boarding not in ('Akurdi','Nigdi Bhakti Shakti','Spine Road','Moshi Toll Naka') then raise exception 'bad_input'; end if;
  -- free seats whose 15-minute hold ran out without a payment
  delete from seat_locks where booking_id in (select id from bookings where status='held' and expires_at < now());
  update bookings set status='expired' where status='held' and expires_at < now();
  v_ref := 'BK' || upper(substr(md5(random()::text),1,6));
  insert into bookings(ref,name,phone,boarding,seats,amount,expires_at)
    values (v_ref, trim(p_name), p_phone, p_boarding, p_seats, v_fare*n, v_exp) returning id into v_id;
  foreach s in array p_seats loop
    if s !~ '^(S1|([1-9]|1[01])[A-D])$' then raise exception 'bad_seats'; end if;
    begin insert into seat_locks(seat,booking_id) values (s, v_id);
    exception when unique_violation then raise exception 'seat_taken'; end;
  end loop;
  return json_build_object('ref',v_ref,'amount',v_fare*n,'expires_at',v_exp);
end $$;

create or replace function submit_payment(p_ref text, p_phone text, p_utr text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if p_utr !~ '^[0-9]{12}$' then return false; end if;
  update bookings set utr=p_utr, status='pending', expires_at=null
   where ref=p_ref and phone=p_phone and status='held' and expires_at > now();
  return found;
end $$;

create or replace function booking_status(p_ref text, p_phone text)
returns text language sql security definer set search_path=public as $$
  select status from bookings where ref=p_ref and phone=p_phone $$;

create or replace function taken_seats()
returns text[] language sql security definer set search_path=public as $$
  select coalesce(array_agg(l.seat), '{}') from seat_locks l join bookings b on b.id=l.booking_id
   where b.status in ('pending','confirmed') or (b.status='held' and b.expires_at > now()) $$;

create or replace function admin_set(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.role() <> 'authenticated' then raise exception 'not_allowed'; end if;
  if p_status = 'confirmed' then
    update bookings set status='confirmed' where id=p_id and status='pending';
  elsif p_status = 'rejected' then
    update bookings set status='rejected' where id=p_id and status='pending';
    delete from seat_locks where booking_id=p_id;
  end if;
end $$;

revoke all on function admin_set(uuid,text) from public, anon;
grant execute on function admin_set(uuid,text) to authenticated;
grant execute on function hold_seats(text[],text,text,text), submit_payment(text,text,text),
  booking_status(text,text), taken_seats() to anon, authenticated;
