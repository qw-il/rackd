import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, NavLink, Route, Routes, useLocation } from 'react-router-dom';
import { WardrobePage } from './pages/Wardrobe';
import { ItemDetailPage } from './pages/ItemDetail';
import { OutfitsPage, OutfitDetailPage } from './pages/Outfits';
import { OutfitBuilderPage } from './pages/OutfitBuilder';
import { CalendarPage } from './pages/Calendar';
import './styles.css';

function App() {
  // The outfit builder has its own Cancel/Save, so give its tray the full height.
  const inBuilder = /^\/outfits\/(new|[^/]+\/edit)$/.test(useLocation().pathname);
  return (
    <>
      <main className={`content${inBuilder ? ' no-tabs' : ''}`}>
        <Routes>
          <Route path="/" element={<WardrobePage />} />
          <Route path="/item/:id" element={<ItemDetailPage />} />
          <Route path="/outfits" element={<OutfitsPage />} />
          <Route path="/outfits/new" element={<OutfitBuilderPage />} />
          <Route path="/outfits/:id" element={<OutfitDetailPage />} />
          <Route path="/outfits/:id/edit" element={<OutfitBuilderPage />} />
          <Route path="/calendar" element={<CalendarPage />} />
          <Route path="*" element={<WardrobePage />} />
        </Routes>
      </main>
      <nav className="tab-bar" aria-label="Main" hidden={inBuilder}>
        <NavLink to="/" end className={({ isActive }) => `tab${isActive ? ' active' : ''}`}>
          <span aria-hidden>🧺</span>Wardrobe
        </NavLink>
        <NavLink to="/outfits" className={({ isActive }) => `tab${isActive ? ' active' : ''}`}>
          <span aria-hidden>🪄</span>Outfits
        </NavLink>
        <NavLink to="/calendar" className={({ isActive }) => `tab${isActive ? ' active' : ''}`}>
          <span aria-hidden>📅</span>Calendar
        </NavLink>
      </nav>
    </>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
);
