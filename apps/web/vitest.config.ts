import { defineConfig } from "vitest/config";
import path from "path";
import dotenv from "dotenv";

dotenv.config({ path: path.resolve(__dirname, ".env") });

export default defineConfig({
  test: { environment: "jsdom", globals: true, fileParallelism: false },
  resolve: {
    alias: {
      "@/generated/prisma": path.resolve(__dirname, "./src/generated/prisma/client.ts"),
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
