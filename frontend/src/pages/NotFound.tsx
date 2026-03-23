import { Link } from "react-router-dom";

export default function NotFound() {
  return (
    <p className="err">
      Page not found.{" "}
      <Link to="/" className="mono">
        Overview
      </Link>
    </p>
  );
}
