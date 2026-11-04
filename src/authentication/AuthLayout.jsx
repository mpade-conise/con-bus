import { Link } from "react-router-dom";
import { Store } from "lucide-react";

export default function AuthLayout({title,subtitle,children,footer}) {
  return <main className="auth-page"><section className="auth-panel"><Link className="auth-brand" to="/"><span><Store size={21}/></span>market<b>hub</b></Link><div className="auth-heading"><h1>{title}</h1><p>{subtitle}</p></div>{children}{footer && <div className="auth-footer">{footer}</div>}</section><aside className="auth-aside"><span className="auth-aside-label">MARKET HUB</span><h2>Your marketplace.<br/>Your business.<br/><em>Your opportunities.</em></h2><p>One account to discover, sell and connect with people across the marketplace.</p><div className="auth-aside-mark"><Store size={58}/></div></aside></main>;
}
