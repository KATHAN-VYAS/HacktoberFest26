import type { Metadata } from "next";
import "./community.css";
import "./refinements.css";

export const metadata: Metadata = {
  title: "TerpCommons · Your campus. Your people.",
  description: "Find your people, share what you know, and get source-backed UMD answers. A student-built community for every stage of being a Terp.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
