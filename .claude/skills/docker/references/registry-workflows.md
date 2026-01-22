# Container Registry Workflows

CI/CD integration patterns for Docker Hub, GitHub Container Registry, and automated workflows.

---

## Registry Options

| Registry | URL | Best For |
|----------|-----|----------|
| Docker Hub | `docker.io` | Public images, official images |
| GitHub Container Registry | `ghcr.io` | GitHub projects, private repos |
| AWS ECR | `<account>.dkr.ecr.<region>.amazonaws.com` | AWS deployments |
| Google Artifact Registry | `<region>-docker.pkg.dev` | GCP deployments |
| Azure Container Registry | `<name>.azurecr.io` | Azure deployments |

---

## Image Tagging Strategies

### Semantic Versioning
```bash
# Tag with version
docker tag myapp:latest myapp:1.0.0
docker tag myapp:latest myapp:1.0
docker tag myapp:latest myapp:1

# Push all tags
docker push myapp:1.0.0
docker push myapp:1.0
docker push myapp:1
```

### Git-based Tagging
```bash
# Tag with commit SHA (immutable)
docker tag myapp:latest myapp:$(git rev-parse --short HEAD)

# Tag with branch name
docker tag myapp:latest myapp:$(git branch --show-current)

# Tag with tag name
docker tag myapp:latest myapp:$(git describe --tags)
```

### Recommended Strategy
```
myapp:latest        # Latest stable (optional, use with caution)
myapp:1.2.3         # Specific version (semantic)
myapp:sha-abc123    # Specific commit (immutable)
myapp:main          # Branch tracking
myapp:pr-42         # Pull request builds
```

---

## Docker Hub

### Login
```bash
# Interactive
docker login

# Non-interactive (CI/CD)
echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
```

### Push Image
```bash
# Tag for Docker Hub
docker tag myapp:latest username/myapp:1.0.0

# Push
docker push username/myapp:1.0.0
```

### GitHub Actions Workflow
```yaml
name: Build and Push to Docker Hub

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  IMAGE_NAME: myapp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ secrets.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=sha,prefix=sha-

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## GitHub Container Registry (GHCR)

### Login
```bash
# Using GitHub token
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Push Image
```bash
# Tag for GHCR
docker tag myapp:latest ghcr.io/username/myapp:1.0.0

# Push
docker push ghcr.io/username/myapp:1.0.0
```

### GitHub Actions Workflow
```yaml
name: Build and Push to GHCR

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix=sha-

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Full CI/CD Pipeline

### With Testing and Security Scanning

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Run tests
        run: pytest --cov

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix=sha-

      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          load: true
          tags: ${{ env.IMAGE_NAME }}:test
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.IMAGE_NAME }}:test
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'

      - name: Push image
        if: github.event_name != 'pull_request'
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Multi-Platform Builds

```yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push multi-platform
  uses: docker/build-push-action@v5
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: true
    tags: ${{ steps.meta.outputs.tags }}
```

---

## Local Registry (for Development)

```bash
# Start local registry
docker run -d -p 5000:5000 --name registry registry:2

# Tag and push
docker tag myapp localhost:5000/myapp
docker push localhost:5000/myapp

# Pull from local registry
docker pull localhost:5000/myapp
```

---

## Best Practices

### Security
- Use read-only tokens where possible
- Rotate credentials regularly
- Scan images before pushing
- Sign images in production

### Performance
- Use BuildKit cache
- Enable GitHub Actions cache
- Use multi-stage builds
- Minimize layers

### Tagging
- Always use specific tags (avoid `latest` in production)
- Include SHA for traceability
- Use semantic versioning for releases
- Tag PR builds for testing
