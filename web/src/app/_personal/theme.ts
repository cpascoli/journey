// Shared by the server pages and the toggle, so it cannot live in a client file.
export const THEME_KEY = "personal-theme";

/**
 * Runs before the page paints, so a visitor who chose the light theme never
 * sees a flash of the dark one. Dark is the default and needs no attribute.
 */
export const THEME_SCRIPT = `try{if(localStorage.getItem("${THEME_KEY}")==="light")document.documentElement.dataset.personalTheme="light"}catch(e){}`;
