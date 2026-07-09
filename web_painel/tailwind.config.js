/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Paleta clínica: neutra, alto contraste, nada do dourado/laranja
        // competitivo do app mobile — este é o painel profissional, não o
        // app gamificado (mesma separação de identidade visual já aplicada
        // ao tema Sênior do app Flutter).
        clinical: {
          bg: '#0B1120',
          surface: '#111827',
          border: '#1F2937',
          primary: '#2563EB',
          accent: '#0EA5E9',
          warning: '#F59E0B',
          critical: '#DC2626',
          success: '#16A34A',
          muted: '#94A3B8',
        },
      },
    },
  },
  plugins: [],
};
