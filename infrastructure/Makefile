TESTPARALLELISM := 8

.PHONY: lint
lint:
	golangci-lint run -c .golangci.yml
	go vet ./...

.PHONY: fix
fix:
	golangci-lint fmt -c .golangci.yml

.PHONY: test
test:
	go test -v -parallel ${TESTPARALLELISM} -timeout 2h -covermode atomic -coverprofile=covprofile ./pkg/...

.PHONY: coverage
coverage:
	go tool cover -html=covprofile -o coverage.html
	@echo "coverage report: $(CURDIR)/coverage.html"
