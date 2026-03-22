import { NavLink, Route, Routes } from "react-router-dom";
import Dashboard from "./pages/Dashboard";
import Slots from "./pages/Slots";
import SlotPage from "./pages/SlotPage";
import BlockPage from "./pages/BlockPage";

export default function App() {
  return (
    <>
      <header>
        <div className="brand">
          <h1 className="brand-title">
            <img
              src={`${import.meta.env.BASE_URL}nemo-logo.png`}
              alt="Nemo"
              className="brand-logo"
            />
          </h1>
          <span className="sub">Lean Ethereum explorer</span>
        </div>
        <nav>
          <NavLink to="/" end>
            Overview
          </NavLink>
          <NavLink to="/slots">Slots</NavLink>
        </nav>
      </header>
      <main>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/slots" element={<Slots />} />
          <Route path="/slot/:slot" element={<SlotPage />} />
          <Route path="/block/:root" element={<BlockPage />} />
        </Routes>
      </main>
    </>
  );
}
