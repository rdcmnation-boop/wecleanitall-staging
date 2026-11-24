// /comercial/ moved to the homepage (/). Keeps section links like /comercial/#quote working.
location.replace("/" + (location.hash === "#quote" ? "#assess" : location.hash));
