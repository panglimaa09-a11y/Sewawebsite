import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#EAF1FF',
        navy: { DEFAULT: '#05070F', 2: '#0A0F22', 3: '#0D132B' },
        neon: { cyan: '#4DE3FF', violet: '#8B7CFF', mint: '#5CF2C4' },
        muted: '#93A0C4',
        dim: '#5C6A93',
      },
      fontFamily: {
        display: ['var(--font-space-grotesk)', 'sans-serif'],
        sans: ['var(--font-jakarta)', 'sans-serif'],
        mono: ['var(--font-jetbrains)', 'monospace'],
      },
    },
  },
  plugins: [],
};

export default config;
