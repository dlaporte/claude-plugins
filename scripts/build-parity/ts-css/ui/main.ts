// The TS entry: no JSX, an imported stylesheet and an imported SVG image.
import icon from "./icon.svg";
import "./theme.css";

const img = document.createElement("img");
img.src = icon;
img.alt = "";
document.body.append(img);
document.body.dataset.marker = "parity-entry-ts";
