import { NavLink, Route, Routes } from "react-router-dom";
import Dashboard from "./pages/Dashboard";
import Slots from "./pages/Slots";
import SlotPage from "./pages/SlotPage";
import BlockPage from "./pages/BlockPage";

const REPO_URL = "https://github.com/ch4r10t33r/nemo";

export default function App() {
  const gitSha = import.meta.env.VITE_APP_GIT_SHA;
  const hasCommit = gitSha !== "unknown" && /^[0-9a-f]{7,40}$/i.test(gitSha);
  const shortSha = hasCommit ? gitSha.slice(0, 7) : null;
  const commitUrl = hasCommit ? `${REPO_URL}/commit/${gitSha}` : REPO_URL;

  return (
    <div className="app-shell">
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
      <footer className="app-footer">
        <p>
          Powered by{" "}
          <a href={REPO_URL} target="_blank" rel="noopener noreferrer">
            ch4r10t33r/nemo
          </a>
          {shortSha != null ? (
            <>
              {" · "}
              <a href={commitUrl} target="_blank" rel="noopener noreferrer" className="mono" title={gitSha}>
                {shortSha}
              </a>
            </>
          ) : null}
        </p>
      </footer>
    </div>
  );
}
