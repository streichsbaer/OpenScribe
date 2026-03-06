(() => {
  const INTERVAL_MS = 5000;

  const initHomeCarousel = () => {
    const carousel = document.querySelector(".hero-carousel");
    const lightbox = document.querySelector(".hero-lightbox");

    if (!carousel || !lightbox || carousel.dataset.ready === "true") {
      return;
    }

    carousel.dataset.ready = "true";

    const slides = Array.from(carousel.querySelectorAll(".hero-carousel-slide"));
    const captions = Array.from(carousel.querySelectorAll(".hero-carousel-caption"));
    const dots = Array.from(carousel.querySelectorAll(".hero-carousel-dot"));
    const lightboxImage = lightbox.querySelector("img");
    const lightboxCaption = lightbox.querySelector(".hero-lightbox-caption");
    const closeButton = lightbox.querySelector(".hero-lightbox-close");
    const closeTargets = Array.from(lightbox.querySelectorAll("[aria-label='Close enlarged screenshot']"));
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    if (!slides.length || slides.length !== captions.length || slides.length !== dots.length) {
      return;
    }

    let activeIndex = 0;
    let timerId = null;

    const isLightboxOpen = () => !lightbox.hidden;

    const syncLightbox = () => {
      const slide = slides[activeIndex];
      const image = slide.querySelector("img");
      const caption = captions[activeIndex];

      if (!image || !lightboxImage || !lightboxCaption) {
        return;
      }

      lightboxImage.src = image.currentSrc || image.src;
      lightboxImage.alt = image.alt;
      lightboxCaption.textContent = caption.textContent || "";
    };

    const render = (nextIndex) => {
      activeIndex = (nextIndex + slides.length) % slides.length;

      slides.forEach((slide, index) => {
        slide.classList.toggle("is-active", index === activeIndex);
      });

      captions.forEach((caption, index) => {
        caption.classList.toggle("is-active", index === activeIndex);
      });

      dots.forEach((dot, index) => {
        const isActive = index === activeIndex;
        dot.classList.toggle("is-active", isActive);
        dot.setAttribute("aria-pressed", String(isActive));
      });

      if (isLightboxOpen()) {
        syncLightbox();
      }
    };

    const stopAutoplay = () => {
      if (timerId !== null) {
        window.clearInterval(timerId);
        timerId = null;
      }
    };

    const startAutoplay = () => {
      if (reducedMotion.matches) {
        return;
      }

      if (isLightboxOpen()) {
        return;
      }

      stopAutoplay();
      timerId = window.setInterval(() => {
        render((activeIndex + 1) % slides.length);
      }, INTERVAL_MS);
    };

    const openLightbox = () => {
      stopAutoplay();
      syncLightbox();
      lightbox.hidden = false;
      document.body.classList.add("hero-lightbox-open");
      closeButton?.focus();
    };

    const closeLightbox = () => {
      if (lightbox.hidden) {
        return;
      }

      lightbox.hidden = true;
      document.body.classList.remove("hero-lightbox-open");
      startAutoplay();
      slides[activeIndex]?.focus();
    };

    const stepSlide = (direction) => {
      render(activeIndex + direction);
    };

    const handleLightboxKeydown = (event) => {
      if (!isLightboxOpen()) {
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        closeLightbox();
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        event.stopPropagation();
        stepSlide(1);
      } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        event.stopPropagation();
        stepSlide(-1);
      }
    };

    slides.forEach((slide, index) => {
      slide.addEventListener("click", openLightbox);
      slide.addEventListener("focus", () => render(index));
    });

    dots.forEach((dot, index) => {
      dot.addEventListener("click", () => {
        render(index);
        startAutoplay();
      });
    });

    closeTargets.forEach((target) => {
      target.addEventListener("click", closeLightbox);
    });

    closeButton?.addEventListener("keydown", handleLightboxKeydown);
    lightbox.addEventListener("keydown", handleLightboxKeydown);
    document.addEventListener("keydown", handleLightboxKeydown);

    carousel.addEventListener("mouseenter", stopAutoplay);
    carousel.addEventListener("mouseleave", startAutoplay);
    carousel.addEventListener("focusin", stopAutoplay);
    carousel.addEventListener("focusout", (event) => {
      if (!carousel.contains(event.relatedTarget)) {
        startAutoplay();
      }
    });

    reducedMotion.addEventListener("change", () => {
      if (reducedMotion.matches) {
        stopAutoplay();
      } else {
        startAutoplay();
      }
    });

    render(activeIndex);
    startAutoplay();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initHomeCarousel, { once: true });
  } else {
    initHomeCarousel();
  }
})();
