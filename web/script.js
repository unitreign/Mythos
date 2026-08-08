'use strict';

/* ─── THEME ─── */
const root = document.documentElement;
const themeBtn = document.getElementById('themeToggle');

function getStoredTheme() {
  return localStorage.getItem('mythos-theme');
}
function getSystemTheme() {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}
function applyTheme(theme) {
  root.setAttribute('data-theme', theme);
  localStorage.setItem('mythos-theme', theme);
}

const initialTheme = getStoredTheme() || getSystemTheme();
applyTheme(initialTheme);

themeBtn.addEventListener('click', () => {
  const next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  applyTheme(next);
});

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
  if (!getStoredTheme()) applyTheme(e.matches ? 'dark' : 'light');
});

/* ─── NAV SCROLL ─── */
const nav = document.getElementById('nav');
let lastScroll = 0;

window.addEventListener('scroll', () => {
  const y = window.scrollY;
  nav.classList.toggle('scrolled', y > 20);
  lastScroll = y;
}, { passive: true });

/* ─── SLIDESHOW ─── */
const slides = [
  { src: '/images/screenshots/ss-browse.png',        caption: 'Browse popular titles' },
  { src: '/images/screenshots/ss-search.png',         caption: 'Search by title' },
  { src: '/images/screenshots/ss-novel-detail.png',   caption: 'Novel details & tracking' },
  { src: '/images/screenshots/ss-chapters.png',        caption: 'Chapter selection' },
  { src: '/images/screenshots/ss-export-options.png',  caption: 'Export options' },
  { src: '/images/screenshots/ss-library.png',         caption: 'Your library' },
  { src: '/images/screenshots/ss-exported-books.png',  caption: 'Exported EPUBs in KOReader' },
  { src: '/images/screenshots/ss-sources.png',         caption: 'Sources & extensions' },
];

const track    = document.getElementById('slideshowTrack');
const dotsEl   = document.getElementById('slideDots');
const prevBtn  = document.getElementById('slidePrev');
const nextBtn  = document.getElementById('slideNext');
const captionEl = document.getElementById('slideCaption');

let current = 0;
let autoTimer = null;
let isDragging = false;
let dragStartX = 0;
let dragCurrentX = 0;

function buildSlideshow() {
  slides.forEach((s, i) => {
    const slide = document.createElement('div');
    slide.className = 'slide';
    slide.setAttribute('role', 'tabpanel');
    slide.setAttribute('aria-label', s.caption);

    const img = document.createElement('img');
    img.src = s.src;
    img.alt = s.caption;
    img.loading = i === 0 ? 'eager' : 'lazy';
    img.draggable = false;

    slide.appendChild(img);
    track.appendChild(slide);

    const dot = document.createElement('button');
    dot.className = 'dot' + (i === 0 ? ' active' : '');
    dot.setAttribute('role', 'tab');
    dot.setAttribute('aria-label', `Go to screenshot ${i + 1}: ${s.caption}`);
    dot.setAttribute('aria-selected', i === 0 ? 'true' : 'false');
    dot.addEventListener('click', () => goTo(i));
    dotsEl.appendChild(dot);
  });
  updateUI();
}

function goTo(index, resetAuto = true) {
  current = (index + slides.length) % slides.length;
  updateUI();
  if (resetAuto) resetAutoplay();
}

function updateUI() {
  track.style.transform = `translateX(-${current * 100}%)`;

  captionEl.textContent = slides[current].caption;

  const dots = dotsEl.querySelectorAll('.dot');
  dots.forEach((d, i) => {
    const active = i === current;
    d.classList.toggle('active', active);
    d.setAttribute('aria-selected', active ? 'true' : 'false');
  });
}

prevBtn.addEventListener('click', () => goTo(current - 1));
nextBtn.addEventListener('click', () => goTo(current + 1));

/* keyboard navigation */
document.addEventListener('keydown', e => {
  if (modalOpen) {
    if (e.key === 'Escape') closeModal();
    if (e.key === 'ArrowLeft') { e.preventDefault(); modalGoTo(-1); }
    if (e.key === 'ArrowRight') { e.preventDefault(); modalGoTo(1); }
    return;
  }
  const ss = document.getElementById('slideshow');
  if (!isInView(ss)) return;
  if (e.key === 'ArrowLeft') { e.preventDefault(); goTo(current - 1); }
  if (e.key === 'ArrowRight') { e.preventDefault(); goTo(current + 1); }
});

/* touch/mouse drag */
function onDragStart(x) {
  isDragging = true;
  dragStartX = x;
  dragCurrentX = x;
  track.style.transition = 'none';
}
function onDragMove(x) {
  if (!isDragging) return;
  dragCurrentX = x;
  const diff = dragCurrentX - dragStartX;
  track.style.transform = `translateX(calc(-${current * 100}% + ${diff}px))`;
}
function onDragEnd() {
  if (!isDragging) return;
  const diff = dragCurrentX - dragStartX;
  isDragging = Math.abs(diff) > 8; // remain true if actual drag occurred (blocks click-as-open)
  track.style.transition = '';
  const threshold = 50;
  if (diff < -threshold) goTo(current + 1);
  else if (diff > threshold) goTo(current - 1);
  else updateUI();
  requestAnimationFrame(() => { isDragging = false; });
}

track.addEventListener('mousedown', e => onDragStart(e.clientX));
window.addEventListener('mousemove', e => { if (isDragging) onDragMove(e.clientX); });
window.addEventListener('mouseup', onDragEnd);

track.addEventListener('touchstart', e => onDragStart(e.touches[0].clientX), { passive: true });
track.addEventListener('touchmove', e => onDragMove(e.touches[0].clientX), { passive: true });
track.addEventListener('touchend', onDragEnd);

/* autoplay */
function startAutoplay() {
  autoTimer = setInterval(() => goTo(current + 1, false), 4500);
}
function resetAutoplay() {
  clearInterval(autoTimer);
  startAutoplay();
}

/* pause on hover/focus */
const slideshowEl = document.getElementById('slideshow');
slideshowEl.addEventListener('mouseenter', () => clearInterval(autoTimer));
slideshowEl.addEventListener('mouseleave', startAutoplay);
slideshowEl.addEventListener('focusin', () => clearInterval(autoTimer));
slideshowEl.addEventListener('focusout', startAutoplay);

buildSlideshow();
startAutoplay();

/* ─── MODAL / LIGHTBOX ─── */
const modalBackdrop = document.getElementById('modalBackdrop');
const modalImg      = document.getElementById('modalImg');
const modalCaption  = document.getElementById('modalCaption');
const modalClose    = document.getElementById('modalClose');
const modalPrev     = document.getElementById('modalPrev');
const modalNext     = document.getElementById('modalNext');
let modalOpen = false;

function openModal(index) {
  current = index;
  updateUI();
  modalImg.src = slides[index].src;
  modalImg.alt = slides[index].caption;
  modalCaption.textContent = slides[index].caption;
  modalBackdrop.hidden = false;
  modalOpen = true;
  document.body.style.overflow = 'hidden';
  modalClose.focus();
}

function closeModal() {
  modalBackdrop.hidden = true;
  modalOpen = false;
  document.body.style.overflow = '';
}

function modalGoTo(dir) {
  const next = (current + dir + slides.length) % slides.length;
  current = next;
  updateUI();
  modalImg.style.animation = 'none';
  modalImg.offsetHeight; // reflow
  modalImg.style.animation = '';
  modalImg.src = slides[next].src;
  modalImg.alt = slides[next].caption;
  modalCaption.textContent = slides[next].caption;
}

modalClose.addEventListener('click', closeModal);
modalPrev.addEventListener('click', () => modalGoTo(-1));
modalNext.addEventListener('click', () => modalGoTo(1));

modalBackdrop.addEventListener('click', e => {
  if (e.target === modalBackdrop) closeModal();
});

/* click on slideshow viewport opens modal */
document.getElementById('slideshow').querySelector('.slideshow-viewport').addEventListener('click', () => {
  if (!isDragging) openModal(current);
});


/* ─── SCROLL REVEAL ─── */
function isInView(el) {
  const r = el.getBoundingClientRect();
  return r.top < window.innerHeight && r.bottom > 0;
}

if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

  document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
} else {
  document.querySelectorAll('.reveal').forEach(el => el.classList.add('visible'));
}

/* stagger children inside grids */
document.querySelectorAll('.features-grid').forEach(grid => {
  grid.querySelectorAll('.reveal').forEach((card, i) => {
    card.style.transitionDelay = `${i * 60}ms`;
  });
});

/* ─── SMOOTH ANCHOR SCROLL ─── */
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const target = document.querySelector(link.getAttribute('href'));
    if (!target) return;
    e.preventDefault();
    const top = target.getBoundingClientRect().top + window.scrollY - 80;
    window.scrollTo({ top, behavior: 'smooth' });
  });
});
