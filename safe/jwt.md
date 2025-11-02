# Understanding JSON Web Tokens (JWT)

- ![jwt](./jwt.jpeg)
Most developers know how to *use* JWTs, but not everyone understands *why* they are used or what's happening under the hood. This document aims to clarify the purpose and mechanics of JWTs.

## What is JWT?

A JSON Web Token (JWT) is an open standard (RFC 7519) that defines a compact and self-contained way for securely transmitting information between parties as a JSON object. This information can be verified and trusted because it is digitally signed.

## Why Use JWT?

JWTs solve several problems in authentication and information exchange:

*   **Statelessness:** The server doesn't need to store session information. Each request carries all the necessary information, which simplifies scalability, especially in distributed systems.
*   **Self-contained:** The JWT can carry user information (claims), reducing the need for database lookups.
*   **Security:** The signature ensures that the token hasn't been tampered with during transit.
*   **Interoperability:** JWTs can be used across different domains and services.

## How Does JWT Work?

A JWT consists of three parts separated by dots (`.`):

1.  **Header:** Typically consists of two parts: the token type (`JWT`) and the signing algorithm being used, such as HMAC SHA256 or RSA.

    ```json
    {
      "alg": "HS256",
      "typ": "JWT"
    }
    ```

2.  **Payload:** Contains the claims. Claims are statements about an entity (typically, the user) and additional data. There are three types of claims:
    *   **Registered claims:** A set of predefined claims which are not mandatory but recommended, such as `iss` (issuer), `exp` (expiration time), `sub` (subject), and `aud` (audience).
    *   **Public claims:** These can be defined at will by those using JWTs. But to avoid collisions, they should be defined in the IANA JSON Web Token Registry or be defined as a URI with a collision-resistant namespace.
    *   **Private claims:** These are the custom claims created to share information between parties that agree on using them.

    ```json
    {
      "sub": "1234567890",
      "name": "John Doe",
      "admin": true,
      "iat": 1516239022
    }
    ```

3.  **Signature:** To create the signature part, you have to take the encoded header, the encoded payload, a secret, the algorithm specified in the header, and sign that. The signature is used to verify the message wasn't changed along the way, and in the case of tokens signed with a private key, it can also verify that the sender of the JWT is who it says it is.

## JWT Authentication Flow

Here is a typical authentication flow using JWTs:

```mermaid
graph TD
    A[User logs in with credentials] --> B{Authentication Server};
    B -- Verifies credentials --> C[Generates and signs JWT];
    C -- Returns JWT to client --> D[Client];
    D -- Stores JWT (e.g., in localStorage) --> E[Client];
    E -- Includes JWT in Authorization header for subsequent requests --> F[Resource Server];
    F -- Verifies JWT signature and claims --> G{Resource Server};
    G -- If valid --> H[Returns protected resource];
    G -- If invalid --> I[Returns an error];
```

## Code Example

Here is an example of a JWT:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

This JWT, when decoded, has the following Header and Payload:

**Header:**

```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

**Payload:**

```json
{
  "sub": "1234567890",
  "name": "John Doe",
  "admin": true,
  "iat": 1516239022
}
```

## Security Best Practices

*   **Keep secrets safe:** The secret used for signing the JWT must be kept confidential.
*   **Use a strong signing algorithm:** Don't use `none` as the algorithm. Use strong algorithms like RS256.
*   **Set an expiration date:** Always set an expiration date (`exp` claim) for your tokens.
*   **Don't store sensitive data in the payload:** The payload is readable by anyone. Don't store sensitive information in it.
*   **Use HTTPS:** Always transmit JWTs over HTTPS to prevent man-in-the-middle attacks.
*   **Consider token revocation:** Have a strategy for revoking tokens if they are compromised.


