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

function decodeEsewaData(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(new TextDecoder().decode(
    Uint8Array.from(atob(normalized), (char) => char.charCodeAt(0)),
  ));
}

export default {
  async fetch(req: Request) {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    try {
      const { data: encoded } = await req.json();
      if (!encoded) return json({ error: "eSewa response data is required" }, 400);

      const secret = Deno.env.get("ESEWA_SECRET_KEY");
      const productCode = Deno.env.get("ESEWA_PRODUCT_CODE");
      const environment = (Deno.env.get("ESEWA_ENV") || "uat").toLowerCase();

      if (!secret || !productCode) {
        return json({ error: "eSewa credentials are not configured on the server" }, 500);
      }

      const payload = decodeEsewaData(encoded);
      if (!payload?.transaction_uuid || !payload?.total_amount || !payload?.signed_field_names || !payload?.signature) {
        return json({ error: "Invalid eSewa response" }, 400);
      }

      if (payload.product_code !== productCode) {
        return json({ error: "Invalid eSewa product code" }, 400);
      }

      const signedMessage = String(payload.signed_field_names)
        .split(",")
        .map((field: string) => `${field}=${payload[field]}`)
        .join(",");

      const expectedSignature = await hmacSha256(secret, signedMessage);
      if (expectedSignature !== payload.signature) {
        return json({ error: "eSewa response signature verification failed" }, 400);
      }

      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

      const { data: order, error: orderError } = await supabase
        .from("orders")
        .select("id,order_number,total,payment_method,payment_status,payment_transaction_uuid")
        .eq("payment_transaction_uuid", payload.transaction_uuid)
        .maybeSingle();

      if (orderError || !order) return json({ error: "Matching order not found" }, 404);
      if (order.payment_method !== "esewa") return json({ error: "Invalid payment method" }, 400);

      const orderTotal = Number(order.total).toFixed(2);
      const responseTotal = Number(payload.total_amount).toFixed(2);

      if (orderTotal !== responseTotal) {
        return json({ error: "eSewa amount does not match the order" }, 400);
      }

      const statusUrl = environment === "production"
        ? "https://epay.esewa.com.np/api/epay/transaction/status/"
        : "https://uat.esewa.com.np/api/epay/transaction/status/";

      const statusResponse = await fetch(
        `${statusUrl}?product_code=${encodeURIComponent(productCode)}&total_amount=${encodeURIComponent(orderTotal)}&transaction_uuid=${encodeURIComponent(payload.transaction_uuid)}`,
      );

      if (!statusResponse.ok) {
        return json({ error: "Could not verify transaction with eSewa" }, 502);
      }

      const statusData = await statusResponse.json();
      const status = String(statusData?.status || "").toUpperCase();

      if (status === "COMPLETE") {
        await supabase
          .from("orders")
          .update({
            payment_status: "paid",
            payment_reference: statusData.refId || payload.transaction_code || null,
          })
          .eq("id", order.id);
      } else if (["CANCELED", "NOT_FOUND", "FULL_REFUND"].includes(status)) {
        await supabase
          .from("orders")
          .update({ payment_status: "payment_failed" })
          .eq("id", order.id);
      }

      return json({
        verified: status === "COMPLETE",
        status,
        order_number: order.order_number,
        total: Number(order.total),
        reference: statusData.refId || payload.transaction_code || null,
      });
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Could not verify eSewa payment" }, 500);
    }
  },
};
