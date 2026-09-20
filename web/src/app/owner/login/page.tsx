import { redirect } from "next/navigation";

import { currentOwner } from "@/lib/auth/access";

import { LoginForm } from "./LoginForm";

export const dynamic = "force-dynamic";

export default async function OwnerLogin() {
  if (await currentOwner()) redirect("/owner");
  return (
    <main className="page compact">
      <p className="eyebrow">Journey owner</p>
      <h1>Welcome back</h1>
      <p className="lede">Use an owner key to manage the journal and invitations.</p>
      <LoginForm />
    </main>
  );
}

