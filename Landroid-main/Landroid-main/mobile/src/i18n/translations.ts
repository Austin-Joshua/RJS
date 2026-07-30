type Dictionary = Record<string, string>;

const en: Dictionary = {
  title: "Landroid",
  map: "Map",
  dashboard: "Dashboard",
  settings: "Settings",
  clearCache: "Clear All Cached Data",
  roleBlocked: "This feature is consultant-only.",
  confidence: "Confidence",
  landHealth: "Land Health",
  plantZones: "Plant Zones",
  valuation: "Valuation"
};

const ta: Dictionary = {
  title: "லாண்ட்ராய்டு",
  map: "வரைபடம்",
  dashboard: "டாஷ்போர்டு",
  settings: "அமைப்புகள்",
  clearCache: "அனைத்து கேச் தரவையும் நீக்கு",
  roleBlocked: "இந்த அம்சம் ஆலோசகருக்கே.",
  confidence: "நம்பகத்தன்மை",
  landHealth: "நில ஆரோக்கியம்",
  plantZones: "தாவர மண்டலங்கள்",
  valuation: "மதிப்பீடு"
};

export const translations: Record<"en" | "ta", Dictionary> = { en, ta };
