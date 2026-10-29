import type { Metadata, Viewport } from "next";
import { Poppins } from "next/font/google";
import { PREFS_BOOT_SCRIPT } from "@/lib/prefs-boot";
import "./design-tokens.css";
import "./ioh-tokens.css";
import "./globals.css";
import "./ui.css";

const poppins = Poppins({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-poppins",
  display: "swap",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F5F9F8" },
    { media: "(prefers-color-scheme: dark)", color: "#0B1513" },
  ],
};

export const metadata: Metadata = {
  title: "Bizplan Java Agent",
  description: "Winning Every Second — AI agent bisnis Circle Java",
  icons: { icon: "/brand/icon_circle_java.png", apple: "/brand/icon_circle_java.png" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id" className={poppins.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: PREFS_BOOT_SCRIPT }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
