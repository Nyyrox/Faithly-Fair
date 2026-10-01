import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

function base64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function hmacSha256(secret: string, message: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return base64(new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)),
  ));
}

export default {
  async fetch(req: Request) {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    try {
      const { order_number, origin } = await req.json();
      if (!order_number || !origin) return json({ error: "order_number and origin are required" }, 400);

      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

      const { data: order, error } = await supabase
        .from("orders")
        .select("order_number,total,payment_method,payment_status,payment_transaction_uuid")
        .eq("order_number", order_number)
        .maybeSingle();

      if (error || !order) return json({ error: "Order not found" }, 404);
      if (order.payment_method !== "esewa") return json({ error: "Order is not an eSewa payment" }, 400);
      if (order.payment_status === "paid") return json({ error: "Order is already paid" }, 409);

      const secret = Deno.env.get("ESEWA_SECRET_KEY");
      const productCode = Deno.env.get("ESEWA_PRODUCT_CODE");
      const environment = (Deno.env.get("ESEWA_ENV") || "uat").toLowerCase();

      if (!secret || !productCode) {
        return json({ error: "eSewa credentials are not configured on the server" }, 500);
      }

      const transactionUuid = order.payment_transaction_uuid || order.order_number;
      const total = Number(order.total).toFixed(2);
      const signedFieldNames = "total_amount,transaction_uuid,product_code";
      const message = `total_amount=${total},transaction_uuid=${transactionUuid},product_code=${productCode}`;
      const signature = await hmacSha256(secret, message);

      const cleanOrigin = String(origin).replace(/\/$/, "");
      const successUrl = `${cleanOrigin}/order/${encodeURIComponent(order.order_number)}?payment=esewa`;
      const failureUrl = `${cleanOrigin}/order/${encodeURIComponent(order.order_number)}?payment=failed`;

      return json({
        endpoint: environment === "production"
          ? "https://epay.esewa.com.np/api/epay/main/v2/form"
          : "https://rc-epay.esewa.com.np/api/epay/main/v2/form",
        fields: {
          amount: total,
          tax_amount: "0",
          total_amount: total,
          transaction_uuid: transactionUuid,
          product_code: productCode,
          product_service_charge: "0",
          product_delivery_charge: "0",
          success_url: successUrl,
          failure_url: failureUrl,
          signed_field_names: signedFieldNames,
          signature,
        },
      });
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Could not initialize eSewa payment" }, 500);
    }
  },
};
