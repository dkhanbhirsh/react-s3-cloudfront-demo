import './App.css'

// This timestamp is "baked in" at build time by Vite.
// It is set in vite.config.js using a define() block that reads new Date()
// when the build runs. Every CI/CD deploy produces a new timestamp,
// giving us visible proof that the deploy went through.
const BUILD_TIME = __BUILD_TIME__

function App() {
  return (
    <div className="container">
      <header>
        <h1>my demo <span className="accent">S3</span> + <span className="accent">CloudFront</span> 👋</h1>
        <p className="subtitle">A sample React app, built with Vite, deployed via GitHub Actions.</p>
      </header>

      <section className="card">
        <div className="card-label">Build timestamp</div>
        <div className="card-value">{BUILD_TIME}</div>
        <div className="card-hint">
          Push a code change to <code>main</code>. GitHub Actions will rebuild,
          redeploy, and this timestamp will update.
        </div>
      </section>

      <section className="stack">
        <h2>Stack</h2>
        <ul>
          <li><strong>Frontend:</strong> React + Vite</li>
          <li><strong>Storage:</strong> AWS S3 (static hosting)</li>
          <li><strong>CDN:</strong> AWS CloudFront (global edge cache + HTTPS)</li>
          <li><strong>CI/CD:</strong> GitHub Actions (auto-deploy on push)</li>
        </ul>
      </section>

      <footer>
        <p>Built by Danish Khan · See <a href="https://github.com/dkhanbhirsh/react-s3-cloudfront-demo/blob/main/README.md" target="_blank" rel="noopener noreferrer" className="readme-link"><code>README.md</code></a> for setup instructions.</p>
      </footer>
    </div>
  )
}

export default App
