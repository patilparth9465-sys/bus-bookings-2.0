// Supabase Edge Function "notify": sends SMS through MSG91 when a booking changes status.
// Triggered by a Database Webhook on table "bookings" (UPDATE). See README step 5-6.
// Secrets needed: WEBHOOK_SECRET, MSG91_AUTHKEY, OWNER_PHONE (10 digits),
//   TPL_OWNER_NEW, TPL_CUSTOMER_OK, TPL_OWNER_OK, TPL_CUSTOMER_NO  (DLT-approved MSG91 template IDs)
// Template variables are sent as var1..var4. Match them to your templates, and check
// MSG91's current "Flow API" docs, because providers change their API from time to time.

const env = (k: string) => Deno.env.get(k) ?? "";

async function sms(mobile: string, template_id: string, vars: Record<string, string>) {
  const res = await fetch("https://control.msg91.com/api/v5/flow/", {
    method: "POST",
    headers: { authkey: env("MSG91_AUTHKEY"), "content-type": "application/json" },
    body: JSON.stringify({ template_id, short_url: "0", recipients: [{ mobiles: "91" + mobile, ...vars }] }),
  });
  console.log("sms", mobile, res.status, await res.text());
}

Deno.serve(async (req) => {
  if (req.headers.get("x-secret") !== env("WEBHOOK_SECRET")) return new Response("no", { status: 401 });
  const { record: b, old_record: o } = await req.json();
  if (!b || (o && o.status === b.status)) return new Response("skip");
  const seats = (b.seats as string[]).join(", ");
  const owner = env("OWNER_PHONE");

  if (b.status === "pending") {
    // var1 ref, var2 seats, var3 amount, var4 UTR
    await sms(owner, env("TPL_OWNER_NEW"), { var1: b.ref, var2: seats, var3: String(b.amount), var4: b.utr });
  } else if (b.status === "confirmed") {
    // var1 name, var2 ref, var3 seats, var4 boarding point
    await sms(b.phone, env("TPL_CUSTOMER_OK"), { var1: b.name, var2: b.ref, var3: seats, var4: b.boarding });
    await sms(owner, env("TPL_OWNER_OK"), { var1: b.ref, var2: seats, var3: b.name, var4: b.phone });
  } else if (b.status === "rejected") {
    // var1 name, var2 ref
    await sms(b.phone, env("TPL_CUSTOMER_NO"), { var1: b.name, var2: b.ref });
  }
  return new Response("ok");
});
