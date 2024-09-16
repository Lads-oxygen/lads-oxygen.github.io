// Apply dark mode class immediately if preference is set
if (localStorage.getItem('darkMode') === 'enabled') {
    document.documentElement.classList.add('dark-mode');
}

document.addEventListener('DOMContentLoaded', (event) => {
    const darkModeCheckbox = document.getElementById('dark-mode-checkbox');
    const darkModeClass = 'dark-mode';
    const moonSvg = document.getElementById('moon-svg');
    const sunSvg = document.getElementById('sun-svg');

    // Apply dark mode class immediately if preference is set
    if (localStorage.getItem('darkMode') === 'enabled') {
        document.documentElement.classList.add(darkModeClass);
        darkModeCheckbox.checked = true;
        moonSvg.style.display = 'block';
        sunSvg.style.display = 'none';
    }

    darkModeCheckbox.addEventListener('change', () => {
        if (darkModeCheckbox.checked) {
            document.documentElement.classList.add(darkModeClass);
            localStorage.setItem('darkMode', 'enabled');
            moonSvg.style.display = 'block';
            sunSvg.style.display = 'none';
        } else {
            document.documentElement.classList.remove(darkModeClass);
            localStorage.setItem('darkMode', 'disabled');
            moonSvg.style.display = 'none';
            sunSvg.style.display = 'block';
        }
    });
});