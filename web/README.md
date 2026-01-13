# Palad App

This is a Ruby on Rails application with a modern frontend stack.

## Prerequisites

- Docker and Docker Compose

## Local Development Setup

1. Clone the repository:
```bash
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
```

2. Set up the project using Docker:
```bash
make setup
```
This command will:
- Build Docker containers
- Install Ruby dependencies (via Bundler)
- Install JavaScript dependencies (via Yarn)
- Create and set up the database

3. Start the development server:
```bash
docker-compose up
```

4. Access the application at `http://localhost:4000`

## Development Commands

### Database Management
- Prepare database: `make db-prepare`
- Reset database: `make db-reset`

### Code Quality and Testing
- Run all linters and tests: `make check`
- Run only linters: `make lint`
- Run only tests: `make test`
- Run Rubocop (Ruby linter): `make rubocop`
- Run Rubocop with auto-correction: `make rubocop-fix`
- Run ESLint (JavaScript linter): `make eslint`
- Run ESLint with auto-correction: `make eslint-fix`
- Run Brakeman security analysis: `make brakeman`
- Run Rails tests: `make rails-test`

### Frontend Development
- Run FSD (Feature-Sliced Design) analysis: `make fsd`
- Fix FSD issues: `make fsd-fix`

### Other Commands
- Open shell in web container: `make shell`
- Show available commands: `make help`

## Project Structure

The project follows a modern architecture with:
- Ruby on Rails backend
- Feature-Sliced Design (FSD) for frontend organization
- Docker-based development environment
- Comprehensive testing and linting setup

## Contributing

1. Create a new branch for your feature
2. Make your changes
3. Run `make check` to ensure all tests and linters pass
4. Submit a pull request

## AWS Vault Configuration

To configure AWS Vault, run: `aws-vault add {your_aws_vault_profile}`

## Remote Execution

To execute into QA container, run:
```
make exec-qa PROFILE={your_aws_vault_profile}
```

## Login to AWS account with AWS-Vault

```
make login_aws PROFILE={your_aws_vault_profile}
```

## Run browser tools server

```
make browser-tools-server
```

It will run browser tools server that will be listening on http://0.0.0.0:3025