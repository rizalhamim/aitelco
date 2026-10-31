const KEY = "ui_prefs";

// Runs in <head> before first paint so the page never flashes the wrong theme.
export const PREFS_BOOT_SCRIPT = `(function(){try{var p=JSON.parse(localStorage.getItem("${KEY}")||"{}");var t=p.theme||(localStorage.getItem("theme")==="dark"?"dark":"light");var e=document.documentElement;var d=t==="dark"||(t==="system"&&matchMedia("(prefers-color-scheme: dark)").matches);if(t!=="system")e.setAttribute("data-theme",t);if(d)e.classList.add("dark");e.dataset.accent=p.accent||"teal";e.dataset.density=p.density||"standar";e.dataset.motion=p.animation===false?"off":"on";if(p.textScale)e.style.fontSize=p.textScale+"%";}catch(_){}})();`;
