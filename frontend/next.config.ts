import type { NextConfig } from "next";

const BACKEND = process.env.BACKEND_URL || "http://localhost:8000";

const nextConfig: NextConfig = {
  devIndicators: false,
  allowedDevOrigins: ["43.129.52.9", "agent-02.bizplan-java.com", "*.bizplan-java.com"],
  async rewrites() {
    return [
      { source: "/api/:path*", destination: `${BACKEND}/api/:path*` },
    ];
  },
};

export default nextConfig;
