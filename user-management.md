---
name: user-management
description: Build full-stack user management applications using Python for the API and Next.js for the interface, leveraging PostgreSQL-native identity, configuration, metering, and job queues (authn, authz ReBAC, config, meter, queue). Use when designing or implementing authentication, authorization, RBAC/ReBAC, session handling, metering, configuration management, and background queues backed by PostgreSQL SQL functions.
---

# PostgreSQL & Python & Next.js User Management System

A comprehensive guide and pattern for building production-grade user management applications with a Python backend (API), Next.js frontend, and a PostgreSQL-native core handling identity, configuration, metering, and job queues via SQL functions.

## Architecture Overview

1. **Database Layer (PostgreSQL Core)**:
   - **Authn**: User accounts, sessions, password hashing, MFA (TOTP), and password reset tokens implemented via SQL functions.
   - **Authz (ReBAC)**: Relationship-based access control, object-permission mapping, and role hierarchies.
   - **Config**: Versioned key-value storage for tenant/user preferences and system flags.
   - **Meter**: Usage tracking with credit/resource reservations and quotas.
   - **Queue**: Background job scheduling with retries and dead-letter handling.

2. **API Layer (Python)**:
   - FastAPI or lightweight async Python web framework interacting with PostgreSQL via robust SQL drivers (`asyncpg` / `psycopg`).
   - Exposes REST/GraphQL endpoints mapping directly to PostgreSQL functions.
   - Session validation, JWT/cookie handling, request context injection.

3. **Frontend Layer (Next.js)**:
   - App Router structure with modular directories for Authentication (`/auth`), User Dashboard (`/dashboard`), Settings & Config (`/settings`), Billing & Metering (`/billing`), and Admin Queue Monitor (`/admin/queues`).
   - Server Actions / API routes interfacing with the Python backend.

---

## Core Modules & Implementation Guide

### 1. Authentication & Session Management (Authn)
- **Database Functions**: `auth.sign_up()`, `auth.sign_in()`, `auth.verify_mfa()`, `auth.reset_password()`.
- **API Endpoints**: 
  - `POST /api/auth/signup`
  - `POST /api/auth/login`
  - `POST /api/auth/logout`
  - `POST /api/auth/mfa/verify`
- **Next.js UI (`/auth/login`, `/auth/signup`, `/auth/mfa`)**:
  - React hook forms with Zod validation.
  - Secure HttpOnly cookie management or Bearer token storage.

### 2. Relationship-Based Access Control (Authz / ReBAC)
- **Database Functions**: `authz.check_permission(user_id, resource_id, action)`, `authz.grant_role()`.
- **API Endpoints**:
  - `GET /api/permissions/check`
  - `POST /api/permissions/grant`
- **Next.js UI**:
  - Higher-order components / middleware checking permission state before rendering sensitive modules or admin panels.

### 3. Versioned Configuration (Config)
- **Database Functions**: `config.get(key, version)`, `config.set(key, value)`.
- **API Endpoints**:
  - `GET /api/config`
  - `PUT /api/config`
- **Next.js UI (`/settings`)**:
  - Dynamic form rendering based on JSON schema returned by configuration endpoints.

### 4. Metering & Quotas (Meter)
- **Database Functions**: `meter.track_usage(user_id, metric_name, quantity)`, `meter.check_quota()`.
- **API Endpoints**:
  - `GET /api/meter/usage`
  - `POST /api/meter/reserve`
- **Next.js UI (`/billing`)**:
  - Usage progress bars, billing period summaries, credit reservation alerts.

### 5. Background Job Queues (Queue)
- **Database Functions**: `queue.enqueue(job_type, payload)`, `queue.poll_next()`.
- **API Endpoints**:
  - `POST /api/jobs`
  - `GET /api/jobs/status`
- **Next.js UI (`/admin/queues`)**:
  - Real-time job monitor showing queued, active, retried, and dead-letter jobs.

---

## Best Practices & Conventions
- **SQL Function Encapsulation**: Keep business logic inside PostgreSQL functions where ACID guarantees and speed matter; let Python handle HTTP routing, serialization, and middleware; let Next.js handle responsive UI, state management, and client-side validation.
- **Error Handling**: Standardize error payloads across Python API (`{"error": {"code": "...", "message": "..."}}`) and catch PostgreSQL exceptions gracefully.
- **Type Safety**: Maintain shared TypeScript interfaces matching Python Pydantic models and PostgreSQL row definitions.