# Automatic transfer path (international)

**Region**: International cluster (e.g. `api.shrimpsend.com` / `ws.shrimpsend.com`)

The chat session no longer shows a transport picker. Send a file and the client tries paths in speed order until one can transfer:

1. HTTP LAN direct push
2. HTTP reverse pull
3. WebRTC peer-to-peer
4. S3 cloud relay (signed-in only)

Web browsers cannot serve LAN HTTP, so **Web → App** uses push only, **App → Web** uses reverse pull only, and **Web → Web** skips HTTP. Guest sessions still use HTTP with those direction rules.

Background `/probe` checks remain internal so a recently failed LAN hop can be skipped; they are not shown as mode dots in the session header.

## Related

- Transfer protocol: `shared/protocol.en.md`
- Connection diagnostic still exists as an internal probe helper, not a chat-bar control.
