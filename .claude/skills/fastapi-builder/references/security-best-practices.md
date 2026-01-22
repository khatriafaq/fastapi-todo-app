# FastAPI Security Best Practices

This document provides security guidelines for FastAPI applications from development to production.

## Security Checklist by Level

### Level 2+ (Basic CRUD) - Baseline Security

- [ ] **Input Validation**: All inputs validated via Pydantic schemas
- [ ] **SQL Injection Prevention**: Use ORM (SQLAlchemy) with parameterized queries
- [ ] **Environment Variables**: No hardcoded secrets (use `.env` files)
- [ ] **Password Storage**: Never store plain text passwords

### Level 3+ (Authentication) - Auth Security

- [ ] **Password Hashing**: Use bcrypt or Argon2 (via passlib)
- [ ] **JWT Security**: Set expiration times, use strong secret keys
- [ ] **HTTPS Only**: Enforce HTTPS in production
- [ ] **Secure Cookies**: Set `httponly`, `secure`, `samesite` flags
- [ ] **Rate Limiting**: Protect login endpoints from brute force

### Level 4+ (Production) - Production Hardening

- [ ] **CORS**: Explicit origin whitelist (never `["*"]` in production)
- [ ] **Debug Mode**: Disabled in production (`debug=False`)
- [ ] **API Docs**: Disable `/docs`, `/redoc` or protect with authentication
- [ ] **Security Headers**: HSTS, X-Content-Type-Options, X-Frame-Options
- [ ] **Dependency Scanning**: Regular vulnerability checks (`pip-audit`)
- [ ] **Error Messages**: No stack traces or sensitive info in responses
- [ ] **Logging**: Sanitize logs (no passwords, tokens)

---

## 1. Input Validation

**Always use Pydantic schemas** for request validation:

```python
from pydantic import BaseModel, EmailStr, validator, Field

class UserCreate(BaseModel):
    email: EmailStr  # Validates email format
    username: str = Field(..., min_length=3, max_length=50)
    age: int = Field(..., ge=0, le=150)  # Between 0 and 150

    @validator('username')
    def username_alphanumeric(cls, v):
        assert v.isalnum(), 'must be alphanumeric'
        return v
```

**Benefits**:
- Automatic type coercion and validation
- Clear error messages for invalid inputs
- Prevents injection attacks via type safety

---

## 2. Authentication & Authorization

### Password Hashing

**NEVER store plain text passwords**. Use `passlib` with bcrypt:

```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)
```

### JWT (JSON Web Tokens)

**Best practices**:

```python
from datetime import datetime, timedelta
from jose import jwt, JWTError
from .config import settings

def create_access_token(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)  # Short expiry

    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt

def verify_token(token: str):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError:
        return None
```

**Configuration**:
```python
# config.py
from pydantic_settings import BaseSettings
import secrets

class Settings(BaseSettings):
    SECRET_KEY: str = secrets.token_urlsafe(32)  # Generate strong key
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    class Config:
        env_file = ".env"
```

**Key security points**:
- Use strong, random `SECRET_KEY` (at least 32 bytes)
- Set reasonable expiration times (15-30 minutes for access tokens)
- Use refresh tokens for longer sessions
- Store `SECRET_KEY` in environment variables, not in code

### OAuth2 Password Flow

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    payload = verify_token(token)
    if payload is None:
        raise credentials_exception

    user_id: int = payload.get("sub")
    if user_id is None:
        raise credentials_exception

    user = get_user_by_id(db, user_id)
    if user is None:
        raise credentials_exception

    return user

# Protected route
@app.get("/users/me")
async def read_users_me(current_user: User = Depends(get_current_user)):
    return current_user
```

### Role-Based Access Control (RBAC)

```python
from enum import Enum
from fastapi import HTTPException, status

class Role(str, Enum):
    USER = "user"
    ADMIN = "admin"

def require_role(required_role: Role):
    def role_checker(current_user: User = Depends(get_current_user)):
        if current_user.role != required_role and current_user.role != Role.ADMIN:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions"
            )
        return current_user
    return role_checker

# Admin-only route
@app.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    current_user: User = Depends(require_role(Role.ADMIN))
):
    # Delete user logic
    pass
```

---

## 3. CORS (Cross-Origin Resource Sharing)

**Development** (permissive):
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # Frontend dev server
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Production** (restrictive):
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://myapp.com",
        "https://www.myapp.com"
    ],  # Explicit whitelist
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],  # Only needed methods
    allow_headers=["Authorization", "Content-Type"],  # Only needed headers
    max_age=3600,  # Cache preflight requests for 1 hour
)
```

**NEVER** use `allow_origins=["*"]` with `allow_credentials=True` - it's a security risk and won't work.

---

## 4. SQL Injection Prevention

**SQLAlchemy ORM** automatically prevents SQL injection:

```python
# ✅ SAFE - ORM handles parameterization
user = db.query(User).filter(User.email == email).first()

# ✅ SAFE - Parameterized query
stmt = text("SELECT * FROM users WHERE email = :email")
result = db.execute(stmt, {"email": email})

# ❌ DANGEROUS - String interpolation
query = f"SELECT * FROM users WHERE email = '{email}'"  # NEVER DO THIS
```

**Always use**:
- ORM methods (`filter`, `where`)
- Parameterized queries with `:param` syntax
- **Never** use f-strings or `.format()` for SQL queries

---

## 5. XSS (Cross-Site Scripting) Prevention

FastAPI returns JSON by default, which is not vulnerable to XSS. However:

**If rendering HTML**:
```python
from fastapi.responses import HTMLResponse
from markupsafe import escape

@app.get("/profile", response_class=HTMLResponse)
async def get_profile(name: str):
    safe_name = escape(name)  # Escape HTML special characters
    return f"<h1>Hello, {safe_name}</h1>"
```

**Better**: Use a templating engine like Jinja2 which auto-escapes:
```python
from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory="templates")

@app.get("/profile")
async def get_profile(request: Request, name: str):
    return templates.TemplateResponse("profile.html", {
        "request": request,
        "name": name  # Jinja2 auto-escapes
    })
```

---

## 6. CSRF (Cross-Site Request Forgery) Protection

**If using cookie-based auth** (not JWT in headers), implement CSRF protection:

```python
from fastapi import Cookie, HTTPException
import secrets

# Generate CSRF token
def generate_csrf_token():
    return secrets.token_urlsafe(32)

# Validate CSRF token
async def validate_csrf(
    csrf_token_cookie: str = Cookie(None),
    csrf_token_header: str = Header(None, alias="X-CSRF-Token")
):
    if not csrf_token_cookie or not csrf_token_header:
        raise HTTPException(status_code=403, detail="Missing CSRF token")

    if csrf_token_cookie != csrf_token_header:
        raise HTTPException(status_code=403, detail="Invalid CSRF token")
```

**Note**: If using JWT in `Authorization` header (not cookies), CSRF is not a concern.

---

## 7. Rate Limiting

Protect against brute force and DDoS:

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.post("/login")
@limiter.limit("5/minute")  # 5 attempts per minute
async def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends()):
    # Authentication logic
    pass
```

**For production**: Use external rate limiting (Nginx, Cloudflare, API Gateway).

---

## 8. Security Headers

Add security headers via middleware:

```python
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["myapp.com", "*.myapp.com"])
```

---

## 9. Environment Configuration

**NEVER hardcode secrets**:

```python
# ❌ BAD
SECRET_KEY = "my-secret-key"
DATABASE_URL = "postgresql://user:password@localhost/db"

# ✅ GOOD
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str
    DATABASE_URL: str
    DEBUG: bool = False

    class Config:
        env_file = ".env"

settings = Settings()
```

**.env file** (NEVER commit to git):
```
SECRET_KEY=randomly-generated-key-here
DATABASE_URL=postgresql://user:password@localhost/db
DEBUG=False
```

**.gitignore**:
```
.env
*.env
```

---

## 10. Error Handling

**Don't leak sensitive information in errors**:

```python
from fastapi import HTTPException

# ❌ BAD - Exposes internal details
@app.get("/users/{user_id}")
async def get_user(user_id: int):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=500, detail=str(e))  # Leaks stack trace

# ✅ GOOD - Generic error message
@app.get("/users/{user_id}")
async def get_user(user_id: int):
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user
    except Exception as e:
        logger.error(f"Error fetching user {user_id}: {e}")  # Log internally
        raise HTTPException(status_code=500, detail="Internal server error")
```

**Global exception handler**:
```python
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )
```

---

## 11. Dependency Vulnerability Scanning

**Regularly scan for vulnerabilities**:

```bash
# Install pip-audit
pip install pip-audit

# Scan dependencies
pip-audit

# Fix vulnerabilities
pip-audit --fix
```

**In CI/CD**:
```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push, pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Run security audit
        run: pip install pip-audit && pip-audit
```

---

## 12. Production Checklist

Before deploying to production:

**Application**:
- [ ] `debug=False` in FastAPI initialization
- [ ] Disable `/docs` and `/redoc` (or protect with auth)
- [ ] Strong `SECRET_KEY` from environment
- [ ] HTTPS enforced (use reverse proxy like Nginx)
- [ ] CORS configured with explicit origins
- [ ] Rate limiting enabled
- [ ] Security headers middleware added

**Authentication**:
- [ ] Passwords hashed with bcrypt/Argon2
- [ ] JWT expiration times set
- [ ] Refresh token rotation implemented
- [ ] Account lockout after failed login attempts

**Database**:
- [ ] Connection credentials from environment
- [ ] Database user has minimal permissions
- [ ] SSL/TLS for database connections
- [ ] Backup and disaster recovery plan

**Infrastructure**:
- [ ] Web Application Firewall (WAF) configured
- [ ] DDoS protection enabled
- [ ] Logging and monitoring active
- [ ] Alerts for suspicious activity
- [ ] Regular security updates and patches

**Compliance** (if applicable):
- [ ] GDPR compliance (data privacy)
- [ ] PCI DSS (if handling payments)
- [ ] HIPAA (if handling health data)
- [ ] SOC 2 (if enterprise)

---

## 13. Common Vulnerabilities

### Path Traversal
```python
# ❌ DANGEROUS
@app.get("/files/{filename}")
async def get_file(filename: str):
    return FileResponse(f"/uploads/{filename}")  # Can access ../../../etc/passwd

# ✅ SAFE
from pathlib import Path

@app.get("/files/{filename}")
async def get_file(filename: str):
    base_path = Path("/uploads")
    file_path = (base_path / filename).resolve()

    # Ensure file is within base_path
    if not str(file_path).startswith(str(base_path)):
        raise HTTPException(status_code=400, detail="Invalid filename")

    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(file_path)
```

### Insecure Deserialization
```python
# ❌ DANGEROUS
import pickle

@app.post("/data")
async def process_data(data: bytes):
    obj = pickle.loads(data)  # Can execute arbitrary code

# ✅ SAFE
# Use JSON (safe) or implement strict validation
@app.post("/data")
async def process_data(data: dict):
    # Pydantic validation ensures safe deserialization
    validated_data = MySchema(**data)
```

---

## Resources

- [FastAPI Security Documentation](https://fastapi.tiangolo.com/tutorial/security/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP API Security](https://owasp.org/www-project-api-security/)
- [Pydantic Security](https://docs.pydantic.dev/latest/)
