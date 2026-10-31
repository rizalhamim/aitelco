import type { Metadata, Viewport } from "next";
import { Poppins, Prompt } from "next/font/google";
import "./ioh-tokens.css";
import "./globals.css";

const poppins = Poppins({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-poppins",
  display: "swap",
});

const prompt = Prompt({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-prompt",
  display: "swap",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
};

export const metadata: Metadata = {
  title: "Bizplan Java Agent",
  description: "Multi-agent analytics assistant for Indosat (IOH) Java",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id" className={`${poppins.variable} ${prompt.variable}`}>
      <body>{children}</body>
    </html>
  );
}
