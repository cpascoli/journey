"use client";

import { useActionState } from "react";

import { login, type LoginState } from "../actions";

const initialState: LoginState = {};

export function LoginForm() {
  const [state, action, pending] = useActionState(login, initialState);
  return (
    <form action={action} className="stack">
      <label htmlFor="key">Owner API key</label>
      <input id="key" name="key" type="password" autoComplete="current-password" required />
      {state.error && <p className="form-error" role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button>
    </form>
  );
}

