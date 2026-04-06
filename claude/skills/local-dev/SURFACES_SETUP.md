# Surfaces Post-Stack Setup

Run after `/local-dev` has the stack up. Handles the extra steps needed
for the surfaces chatbot to work end-to-end.

```
/local-dev surfaces-setup
```

## What it does

1. Reindex Elasticsearch (CustomerProfiles from mikasa, Users from lockbox)
2. Lockbox setup (bundle install, migrate, seed)
3. Restart lockbox + traefik (pick up ES data and new routes)
4. Surfaces DB migration
5. Seed opportunity engagement data for the logged-in user
6. Set passwords on seed users (avoid MailHog magic links)

## Steps

### 1. Reindex Elasticsearch

ES starts empty on each cold start. Mikasa CustomerProfile data must be
indexed so lockbox can populate JWT v2.9 fields.

```bash
docker exec mikasa bundle exec rails runner "
  CustomerProfile.__elasticsearch__.create_index!(force: true)
  CustomerProfile.__elasticsearch__.import(force: true)
"

docker exec lockbox bundle exec rails runner "
  User.__elasticsearch__.create_index!(force: true)
  User.__elasticsearch__.import(force: true)
"
```

Verify: `curl -sk https://es.homebot.test/customers-development/_count`
should return count > 0.

### 2. Lockbox setup

```bash
docker exec lockbox bundle install
docker exec lockbox bundle exec rails db:migrate
docker exec lockbox bundle exec rails db:seed
```

### 3. Restart lockbox and traefik

Lockbox must restart to pick up fresh ES data for JWT generation.
Traefik restart picks up new route config.

```bash
docker restart lockbox
docker restart hbdev_traefik
```

Wait for lockbox Puma — poll `docker logs --tail 3 lockbox` until
"Listening on" appears.

### 4. Surfaces DB migration

```bash
cd ~/Sites/homebotapp/surfaces && pnpm --filter @homebotapp/ai-mastra migrate:up
```

### 5. Seed CustomerGPT data (opportunity lists + engagement)

The standard `make seed` / `db:seed` creates customer profiles and clients
but does NOT create opportunity lists or engagement data. These are specific
to the CustomerGPT feature. Without them, the AI agent returns
"no opportunities found."

```bash
# Get the customer_profile_id for the test LO
docker exec mikasa bundle exec rails runner "
  puts CustomerProfile.where(\"email LIKE '%lenderIndividual-1%'\").last.id
"

# Create opportunity list definitions (Ready to Refi, High Equity, etc.)
# Replace CP_ID with the ID from above
docker exec mikasa bundle exec rails runner "
  OpportunityLists::CreateDefaults.call(customer_profile: CustomerProfile.find('CP_ID'))
"

# Seed engagement data for those opportunity lists
docker exec mikasa bundle exec rake seed:opportunity_engagement_clients[CP_ID]
```

All three commands must run in this order — lists must exist before
engagement data can reference them.

### 6. Set passwords on seed users

Seed user names are randomized (Faker). Set passwords to avoid MailHog.

```bash
docker exec lockbox bundle exec rails runner "
  User.where('email ILIKE ?', '%lenderIndividual%').each do |u|
    u.update!(password: 'Secret123!')
    puts \"Set password for: #{u.email}\"
  end
"
```

### 7. Verify JWT v2.9 fields

```bash
docker exec lockbox bundle exec rails runner '
  u = User.where("email ILIKE ?", "%lenderIndividual%").first
  decoded = JWTToken.decode(JWTToken.create_access_token(user: u, kind: "access", expires_at: 1.hour.from_now.to_i))
  puts decoded[:payload].select { |k,_| %w[audience_type customer_id customer_state customer_type].include?(k) }.inspect
'
```

Should show `audience_type: "customer"`, `customer_id: <mikasa UUID>`, etc.

## After setup

- Start surfaces: `cd ~/Sites/homebotapp/surfaces && pnpm dev`
- Accept self-signed certs in Chrome for both:
  - `https://surfaces-lab-next.homebot.test`
  - `https://surfaces-ai-mastra.homebot.test`
- Log out and back in for a fresh v2.9 JWT
- Password for seed users: `Secret123!`
