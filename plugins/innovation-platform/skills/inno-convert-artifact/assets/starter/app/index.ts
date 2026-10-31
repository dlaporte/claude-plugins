// A converted Claude artifact, served as a function app. The interface lives
// in app/ui/ and the platform's CI builds it into app/.ui-build/ui.ts (the
// contract's "Browser interface"); this Worker serves the page, the two
// built files, the signed-in caller, and the artifact's saved data.
import { UI_SCRIPT, UI_SCRIPT_PATH, UI_STYLES, UI_STYLES_PATH } from "./.ui-build/ui";
import { currentUser } from "./identity";
import { handleStorage } from "./storage";

export interface Env {
  DATA: D1Database;
}

const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join("; ");

const SECURITY_HEADERS = {
  "Content-Security-Policy": CSP,
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};

// The page names only the two built files, by their content-hashed paths:
// no caller data is ever written into it.
const PAGE = [
  "<!doctype html>",
  '<html lang="en">',
  "<head>",
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  "<title>APP_TITLE</title>",
  '<link rel="stylesheet" href="' + UI_STYLES_PATH + '">',
  '<script type="module" src="' + UI_SCRIPT_PATH + '"></script>',
  "</head>",
  "<body>",
  '<div id="root"></div>',
  "</body>",
  "</html>",
].join("\n");

function asset(body: string, type: string): Response {
  return new Response(body, {
    headers: { ...SECURITY_HEADERS, "Content-Type": type, "Cache-Control": "public, max-age=31536000, immutable" },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/healthz") return new Response("ok");

    if (request.method === "GET" && path === UI_SCRIPT_PATH) return asset(UI_SCRIPT, "text/javascript; charset=utf-8");
    if (request.method === "GET" && path === UI_STYLES_PATH) return asset(UI_STYLES, "text/css; charset=utf-8");

    if (path === "/api/me" && request.method === "GET") {
      const caller = currentUser(request.headers);
      return Response.json(caller ? { email: caller.email } : { email: null }, {
        headers: { ...SECURITY_HEADERS, "Cache-Control": "private, no-store" },
      });
    }

    if (path === "/api/storage") return handleStorage(request, env, currentUser(request.headers), SECURITY_HEADERS);

    if (request.method === "GET" && path === "/") {
      return new Response(PAGE, {
        headers: { ...SECURITY_HEADERS, "Content-Type": "text/html; charset=utf-8", "Cache-Control": "private, no-store" },
      });
    }

    return new Response("not found", { status: 404, headers: SECURITY_HEADERS });
  },
};
