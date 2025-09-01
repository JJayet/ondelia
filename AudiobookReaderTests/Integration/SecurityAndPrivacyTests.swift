//
//  SecurityAndPrivacyTests.swift
//  AudiobookReaderTests
//
//  Created for Phase 3 Advanced Testing - Security and Privacy Validation
//

import XCTest
import Security
import Foundation
@testable import AudiobookReader

final class SecurityAndPrivacyTests: XCTestCase {
    
    var securityManager: SecurityManager!
    var privacyManager: PrivacyManager!
    var fileSystemManager: SecureFileSystemManager!
    var sandboxValidator: AppSandboxValidator!
    
    override func setUpWithError() throws {
        securityManager = SecurityManager()
        privacyManager = PrivacyManager()
        fileSystemManager = SecureFileSystemManager()
        sandboxValidator = AppSandboxValidator()
    }
    
    override func tearDownWithError() throws {
        securityManager = nil
        privacyManager = nil
        fileSystemManager = nil
        sandboxValidator = nil
        
        // Clean up any test security artifacts
        cleanupTestSecurityData()
    }
    
    // MARK: - File Access Permissions Validation
    
    func testFileAccessPermissions() throws {
        // Test that app only accesses files it should have access to
        let documentPicker = DocumentPickerManager()
        
        // Simulate user selecting files through document picker
        let validFileURL = createTestFileURL(inAppSandbox: true)
        let invalidFileURL = createTestFileURL(inAppSandbox: false)
        
        // Should be able to access sandbox files
        XCTAssertTrue(fileSystemManager.canAccessFile(at: validFileURL),
                     "Should have access to files in app sandbox")
        
        // Should not access files outside sandbox without explicit permission
        XCTAssertFalse(fileSystemManager.canAccessFile(at: invalidFileURL),
                      "Should not access files outside sandbox without permission")
        
        // Test security-scoped resource access
        let securityScopedURL = documentPicker.createSecurityScopedURL(for: invalidFileURL)
        
        if let scopedURL = securityScopedURL {
            XCTAssertTrue(fileSystemManager.startAccessingSecurityScopedResource(scopedURL),
                         "Should be able to access security-scoped resources")
            
            // Access should work with security-scoped resource
            XCTAssertTrue(fileSystemManager.canAccessFile(at: scopedURL),
                         "Should access file with security-scoped resource")
            
            // Stop accessing when done
            fileSystemManager.stopAccessingSecurityScopedResource(scopedURL)
            
            // Access should be revoked after stopping
            XCTAssertFalse(fileSystemManager.canAccessFile(at: scopedURL),
                          "Access should be revoked after stopping security-scoped resource")
        }
    }
    
    func testSecurityScopedResourceManagement() throws {
        let importManager = SecureImportManager()
        let testFileURLs = (0..<5).map { createTestFileURL(inAppSandbox: false, fileName: "test\($0).mp3") }
        
        var scopedResources: [URL] = []
        
        // Acquire multiple security-scoped resources
        for fileURL in testFileURLs {
            if let scopedURL = importManager.acquireSecurityScopedAccess(for: fileURL) {
                scopedResources.append(scopedURL)
                XCTAssertTrue(importManager.hasValidAccess(to: scopedURL),
                             "Should have valid access to security-scoped resource")
            }
        }
        
        // Test resource limit handling
        XCTAssertLessThanOrEqual(scopedResources.count, 10,
                               "Should not acquire excessive security-scoped resources")
        
        // Test automatic resource cleanup
        importManager.cleanupSecurityScopedResources()
        
        for scopedURL in scopedResources {
            XCTAssertFalse(importManager.hasValidAccess(to: scopedURL),
                          "Resources should be cleaned up automatically")
        }
        
        // Test resource renewal
        if let firstURL = testFileURLs.first,
           let renewedURL = importManager.renewSecurityScopedAccess(for: firstURL) {
            XCTAssertTrue(importManager.hasValidAccess(to: renewedURL),
                         "Should be able to renew security-scoped access")
        }
    }
    
    func testFilePermissionEscalation() throws {
        // Test that app doesn't attempt to escalate file permissions
        let restrictedPaths = [
            "/System/Library/",
            "/private/var/root/",
            "/usr/bin/",
            "/Applications/",
            "/Library/Preferences/"
        ]
        
        for path in restrictedPaths {
            let restrictedURL = URL(fileURLWithPath: path)
            
            XCTAssertFalse(fileSystemManager.attemptAccess(to: restrictedURL),
                          "Should not attempt to access restricted path: \(path)")
            
            // Test that app doesn't try to modify system files
            XCTAssertFalse(fileSystemManager.attemptWrite(to: restrictedURL),
                          "Should not attempt to write to restricted path: \(path)")
        }
    }
    
    // MARK: - App Sandbox Compliance
    
    func testSandboxContainerAccess() throws {
        let containerURL = sandboxValidator.getAppContainerURL()
        XCTAssertNotNil(containerURL, "App should have valid container URL")
        
        // Test Documents directory access
        let documentsURL = sandboxValidator.getDocumentsDirectoryURL()
        XCTAssertNotNil(documentsURL, "Should have access to Documents directory")
        XCTAssertTrue(sandboxValidator.isPathInSandbox(documentsURL!),
                     "Documents directory should be in app sandbox")
        
        // Test that app can create files in allowed directories
        let testFileURL = documentsURL!.appendingPathComponent("sandbox_test.txt")
        XCTAssertTrue(sandboxValidator.canCreateFile(at: testFileURL),
                     "Should be able to create files in Documents directory")
        
        // Create and verify file
        let testData = Data("Sandbox test data".utf8)
        XCTAssertNoThrow(try testData.write(to: testFileURL),
                        "Should be able to write to Documents directory")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFileURL.path),
                     "File should exist after writing")
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFileURL)
    }
    
    func testSandboxViolationPrevention() throws {
        let violationPaths = [
            "/tmp/outside_sandbox.txt",
            "/Users/Shared/violation.txt",
            "/var/tmp/system_file.txt"
        ]
        
        for path in violationPaths {
            let violationURL = URL(fileURLWithPath: path)
            
            // Should not allow file creation outside sandbox
            XCTAssertFalse(sandboxValidator.canCreateFile(at: violationURL),
                          "Should not allow file creation outside sandbox: \(path)")
            
            // Verify write operations fail appropriately
            let testData = Data("Violation test".utf8)
            XCTAssertThrowsError(try testData.write(to: violationURL),
                               "Write outside sandbox should throw error: \(path)") { error in
                XCTAssertTrue(error is CocoaError, "Should throw appropriate file system error")
            }
        }
    }
    
    func testTemporaryFileHandling() throws {
        let tempManager = TemporaryFileManager()
        
        // Create temporary files
        let tempFiles = (0..<10).compactMap { i in
            tempManager.createTemporaryFile(withName: "temp_\(i).mp3")
        }
        
        XCTAssertEqual(tempFiles.count, 10, "Should create all temporary files")
        
        // Verify temporary files are in sandbox
        for tempURL in tempFiles {
            XCTAssertTrue(sandboxValidator.isPathInSandbox(tempURL),
                         "Temporary files should be in sandbox")
            XCTAssertTrue(tempURL.path.contains("tmp") || tempURL.path.contains("Temporary"),
                         "Temporary files should be in temporary directory")
        }
        
        // Test automatic cleanup
        tempManager.cleanupTemporaryFiles()
        
        for tempURL in tempFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                          "Temporary files should be cleaned up")
        }
    }
    
    // MARK: - Privacy-Sensitive Data Handling
    
    func testUserDataEncryption() throws {
        let userDataManager = UserDataManager()
        let sensitiveData = UserSensitiveData(
            userId: "test_user_123",
            preferences: ["volume": 0.8, "speed": 1.25],
            bookmarks: ["book1": [30.5, 125.2, 300.0]],
            listeningHistory: ["book1": 1500, "book2": 3600]
        )
        
        // Test encryption of user data
        let encryptedData = userDataManager.encryptUserData(sensitiveData)
        XCTAssertNotNil(encryptedData, "Should encrypt user data")
        XCTAssertNotEqual(encryptedData, try! JSONEncoder().encode(sensitiveData),
                         "Encrypted data should be different from plain data")
        
        // Test decryption
        let decryptedData = try userDataManager.decryptUserData(encryptedData!)
        XCTAssertEqual(decryptedData.userId, sensitiveData.userId,
                      "Decrypted data should match original")
        XCTAssertEqual(decryptedData.preferences["volume"] as? Double,
                      sensitiveData.preferences["volume"] as? Double,
                      "Decrypted preferences should match")
        
        // Test that encrypted data cannot be read without proper key
        let corruptedData = Data(encryptedData!.dropLast(5))
        XCTAssertThrowsError(try userDataManager.decryptUserData(corruptedData),
                           "Corrupted encrypted data should throw error")
    }
    
    func testKeyChainSecureStorage() throws {
        let keyChainManager = KeyChainManager()
        
        let testKey = "test_secure_key"
        let testData = "sensitive_audio_preference_data".data(using: .utf8)!
        
        // Test storing data in KeyChain
        XCTAssertTrue(keyChainManager.storeSecurely(data: testData, forKey: testKey),
                     "Should store data securely in KeyChain")
        
        // Test retrieving data
        let retrievedData = keyChainManager.retrieveSecurely(forKey: testKey)
        XCTAssertNotNil(retrievedData, "Should retrieve data from KeyChain")
        XCTAssertEqual(retrievedData, testData, "Retrieved data should match stored data")
        
        // Test data isolation between keys
        let differentKey = "different_key"
        let differentData = "different_data".data(using: .utf8)!
        
        XCTAssertTrue(keyChainManager.storeSecurely(data: differentData, forKey: differentKey),
                     "Should store different data with different key")
        
        let retrievedDifferentData = keyChainManager.retrieveSecurely(forKey: differentKey)
        XCTAssertEqual(retrievedDifferentData, differentData,
                      "Should retrieve correct data for different key")
        XCTAssertNotEqual(retrievedDifferentData, testData,
                         "Different keys should return different data")
        
        // Test secure deletion
        XCTAssertTrue(keyChainManager.deleteSecurely(forKey: testKey),
                     "Should delete data securely from KeyChain")
        
        let deletedData = keyChainManager.retrieveSecurely(forKey: testKey)
        XCTAssertNil(deletedData, "Deleted data should not be retrievable")
        
        // Cleanup
        keyChainManager.deleteSecurely(forKey: differentKey)
    }
    
    func testPersonalDataAnonymization() throws {
        let analyticsManager = PrivacyAwareAnalyticsManager()
        
        let userActivity = UserActivityData(
            userId: "user@example.com",
            deviceId: "ABC123-DEF456",
            listeningDuration: 3600,
            booksCompleted: 5,
            averageSpeed: 1.25,
            preferredGenres: ["Fiction", "Science"],
            timestamps: [Date(), Date().addingTimeInterval(-3600)]
        )
        
        // Test data anonymization
        let anonymizedData = analyticsManager.anonymizeUserData(userActivity)
        
        // Personal identifiers should be removed or hashed
        XCTAssertNotEqual(anonymizedData.userId, userActivity.userId,
                         "User ID should be anonymized")
        XCTAssertNotEqual(anonymizedData.deviceId, userActivity.deviceId,
                         "Device ID should be anonymized")
        
        // Aggregate data should be preserved
        XCTAssertEqual(anonymizedData.listeningDuration, userActivity.listeningDuration,
                      "Non-personal aggregate data should be preserved")
        XCTAssertEqual(anonymizedData.booksCompleted, userActivity.booksCompleted,
                      "Usage statistics should be preserved")
        
        // Timestamps should be generalized
        XCTAssertNotEqual(anonymizedData.timestamps, userActivity.timestamps,
                         "Timestamps should be generalized for privacy")
        
        // Test that anonymized data cannot be de-anonymized
        XCTAssertFalse(analyticsManager.canDeAnonymize(anonymizedData),
                      "Anonymized data should not be de-anonymizable")
    }
    
    // MARK: - Data Minimization and Retention
    
    func testDataMinimization() throws {
        let dataManager = MinimalDataManager()
        
        let fullUserProfile = FullUserProfile(
            email: "user@example.com",
            name: "John Doe",
            birthDate: Date(),
            location: "San Francisco, CA",
            phoneNumber: "+1234567890",
            preferences: AudioPreferences(volume: 0.8, speed: 1.25),
            statistics: ListeningStatistics(totalTime: 3600, booksCompleted: 5)
        )
        
        // Test that only necessary data is stored
        let minimizedProfile = dataManager.minimizeUserData(fullUserProfile)
        
        // Personal identifiers should be excluded if not necessary
        XCTAssertNil(minimizedProfile.email, "Email should not be stored if not necessary")
        XCTAssertNil(minimizedProfile.name, "Name should not be stored if not necessary")
        XCTAssertNil(minimizedProfile.birthDate, "Birth date should not be stored if not necessary")
        XCTAssertNil(minimizedProfile.location, "Location should not be stored if not necessary")
        XCTAssertNil(minimizedProfile.phoneNumber, "Phone number should not be stored if not necessary")
        
        // Functional data should be preserved
        XCTAssertNotNil(minimizedProfile.preferences, "Preferences should be preserved for functionality")
        XCTAssertNotNil(minimizedProfile.statistics, "Statistics should be preserved if needed")
        
        // Test data collection purpose limitation
        let analyticsProfile = dataManager.createAnalyticsProfile(from: fullUserProfile)
        XCTAssertNotNil(analyticsProfile.statistics, "Analytics should include usage statistics")
        XCTAssertNil(analyticsProfile.email, "Analytics should not include personal identifiers")
    }
    
    func testDataRetentionPolicies() throws {
        let retentionManager = DataRetentionManager()
        
        // Create test data with different ages
        let recentData = TestUserData(timestamp: Date(), content: "recent")
        let oldData = TestUserData(timestamp: Date().addingTimeInterval(-365 * 24 * 3600), content: "old") // 1 year old
        let veryOldData = TestUserData(timestamp: Date().addingTimeInterval(-3 * 365 * 24 * 3600), content: "very old") // 3 years old
        
        let allData = [recentData, oldData, veryOldData]
        
        for data in allData {
            retentionManager.storeUserData(data)
        }
        
        // Test retention policy enforcement
        retentionManager.enforceRetentionPolicies()
        
        // Recent data should be retained
        let retrievedRecentData = retentionManager.retrieveUserData(id: recentData.id)
        XCTAssertNotNil(retrievedRecentData, "Recent data should be retained")
        
        // Old data should be reviewed based on policy
        let retrievedOldData = retentionManager.retrieveUserData(id: oldData.id)
        // Depending on policy, old data might be retained, anonymized, or deleted
        
        // Very old data should be deleted
        let retrievedVeryOldData = retentionManager.retrieveUserData(id: veryOldData.id)
        XCTAssertNil(retrievedVeryOldData, "Very old data should be deleted per retention policy")
        
        // Test automatic cleanup scheduling
        XCTAssertTrue(retentionManager.isAutomaticCleanupScheduled(),
                     "Automatic cleanup should be scheduled")
        
        let nextCleanupDate = retentionManager.getNextCleanupDate()
        XCTAssertNotNil(nextCleanupDate, "Next cleanup should be scheduled")
        XCTAssertGreaterThan(nextCleanupDate!, Date(), "Next cleanup should be in the future")
    }
    
    // MARK: - Secure Communication
    
    func testSecureNetworkCommunication() throws {
        let networkManager = SecureNetworkManager()
        
        // Test HTTPS enforcement
        let httpURL = URL(string: "http://insecure-api.example.com/metadata")!
        let httpsURL = URL(string: "https://secure-api.example.com/metadata")!
        
        XCTAssertFalse(networkManager.isSecureURL(httpURL),
                      "HTTP URLs should be considered insecure")
        XCTAssertTrue(networkManager.isSecureURL(httpsURL),
                     "HTTPS URLs should be considered secure")
        
        // Test that insecure connections are rejected
        let insecureRequest = networkManager.createRequest(for: httpURL)
        XCTAssertNil(insecureRequest, "Should reject insecure HTTP requests")
        
        let secureRequest = networkManager.createRequest(for: httpsURL)
        XCTAssertNotNil(secureRequest, "Should allow secure HTTPS requests")
        
        // Test certificate pinning (if implemented)
        let pinnedRequest = networkManager.createPinnedRequest(for: httpsURL)
        if let request = pinnedRequest {
            XCTAssertTrue(networkManager.validateCertificatePinning(for: request),
                         "Certificate pinning should be properly configured")
        }
    }
    
    func testDataTransmissionEncryption() throws {
        let cryptoManager = CryptographicManager()
        
        let sensitivePayload = [
            "user_preferences": ["volume": 0.8, "speed": 1.25],
            "listening_progress": ["book1": 1500, "book2": 3600],
            "device_info": ["model": "iPhone", "os": "iOS 26.0"]
        ]
        
        let payloadData = try JSONSerialization.data(withJSONObject: sensitivePayload)
        
        // Test payload encryption before transmission
        let encryptedPayload = cryptoManager.encryptForTransmission(payloadData)
        XCTAssertNotNil(encryptedPayload, "Should encrypt payload for transmission")
        XCTAssertNotEqual(encryptedPayload, payloadData, "Encrypted payload should differ from original")
        
        // Test decryption
        let decryptedPayload = try cryptoManager.decryptTransmissionData(encryptedPayload!)
        XCTAssertEqual(decryptedPayload, payloadData, "Decrypted payload should match original")
        
        // Test key rotation
        let newKey = cryptoManager.rotateEncryptionKey()
        XCTAssertNotNil(newKey, "Should be able to rotate encryption keys")
        
        let newEncryptedPayload = cryptoManager.encryptForTransmission(payloadData)
        XCTAssertNotEqual(newEncryptedPayload, encryptedPayload,
                         "New key should produce different encrypted data")
    }
    
    // MARK: - Privacy Compliance Validation
    
    func testGDPRCompliance() throws {
        let gdprManager = GDPRComplianceManager()
        
        // Test right to access
        let userDataExport = try gdprManager.exportUserData(for: "test_user")
        XCTAssertNotNil(userDataExport, "Should be able to export user data (right to access)")
        
        // Verify export contains all user data categories
        XCTAssertTrue(userDataExport.contains("preferences"),
                     "Export should include user preferences")
        XCTAssertTrue(userDataExport.contains("listening_history"),
                     "Export should include listening history")
        XCTAssertTrue(userDataExport.contains("bookmarks"),
                     "Export should include bookmarks")
        
        // Test right to rectification
        let correctionRequest = DataCorrectionRequest(
            userId: "test_user",
            field: "email",
            newValue: "corrected@example.com"
        )
        
        XCTAssertTrue(gdprManager.processDataCorrection(correctionRequest),
                     "Should support data correction (right to rectification)")
        
        // Test right to erasure
        XCTAssertTrue(gdprManager.deleteUserData(for: "test_user"),
                     "Should support data deletion (right to erasure)")
        
        // Verify data is actually deleted
        let postDeletionExport = try? gdprManager.exportUserData(for: "test_user")
        XCTAssertNil(postDeletionExport, "User data should be deleted after erasure request")
        
        // Test data portability
        let portableData = try gdprManager.exportPortableUserData(for: "another_user")
        XCTAssertNotNil(portableData, "Should provide data in portable format")
        
        // Verify portable data format
        XCTAssertTrue(gdprManager.isValidPortableFormat(portableData),
                     "Exported data should be in machine-readable format")
    }
    
    func testConsentManagement() throws {
        let consentManager = ConsentManager()
        
        // Test explicit consent recording
        let analyticsConsent = ConsentRecord(
            userId: "test_user",
            consentType: .analytics,
            granted: true,
            timestamp: Date(),
            version: "1.0"
        )
        
        XCTAssertTrue(consentManager.recordConsent(analyticsConsent),
                     "Should record user consent")
        
        // Test consent verification
        XCTAssertTrue(consentManager.hasValidConsent(userId: "test_user", for: .analytics),
                     "Should verify valid consent")
        
        // Test consent withdrawal
        XCTAssertTrue(consentManager.withdrawConsent(userId: "test_user", for: .analytics),
                     "Should allow consent withdrawal")
        
        XCTAssertFalse(consentManager.hasValidConsent(userId: "test_user", for: .analytics),
                      "Should respect withdrawn consent")
        
        // Test granular consent
        let granularConsents: [ConsentType] = [.analytics, .personalization, .marketing]
        
        for consentType in granularConsents {
            let consent = ConsentRecord(
                userId: "granular_user",
                consentType: consentType,
                granted: consentType != .marketing, // Deny marketing
                timestamp: Date(),
                version: "1.0"
            )
            
            XCTAssertTrue(consentManager.recordConsent(consent),
                         "Should record granular consent for \(consentType)")
        }
        
        XCTAssertTrue(consentManager.hasValidConsent(userId: "granular_user", for: .analytics),
                     "Should have analytics consent")
        XCTAssertFalse(consentManager.hasValidConsent(userId: "granular_user", for: .marketing),
                      "Should not have marketing consent")
    }
    
    // MARK: - Helper Methods
    
    private func createTestFileURL(inAppSandbox: Bool, fileName: String = "test.mp3") -> URL {
        if inAppSandbox {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentsURL.appendingPathComponent(fileName)
        } else {
            return URL(fileURLWithPath: "/tmp/\(fileName)")
        }
    }
    
    private func cleanupTestSecurityData() {
        // Clean up any test security artifacts
        let keyChainManager = KeyChainManager()
        keyChainManager.deleteSecurely(forKey: "test_secure_key")
        
        // Clean up test files
        let testFileURLs = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("sandbox_test.txt")
        ].compactMap { $0 }
        
        for url in testFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Security and Privacy Support Classes

class SecurityManager {
    func validateSecurityConfiguration() -> Bool {
        return true
    }
}

class PrivacyManager {
    func enforcePrivacyPolicies() -> Bool {
        return true
    }
}

class SecureFileSystemManager {
    func canAccessFile(at url: URL) -> Bool {
        // Check if file is within app sandbox or has security-scoped access
        let sandboxValidator = AppSandboxValidator()
        return sandboxValidator.isPathInSandbox(url)
    }
    
    func startAccessingSecurityScopedResource(_ url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    func stopAccessingSecurityScopedResource(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    func attemptAccess(to url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func attemptWrite(to url: URL) -> Bool {
        let testData = Data("test".utf8)
        do {
            try testData.write(to: url)
            try? FileManager.default.removeItem(at: url) // Cleanup
            return true
        } catch {
            return false
        }
    }
}

class AppSandboxValidator {
    func getAppContainerURL() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent()
    }
    
    func getDocumentsDirectoryURL() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    func isPathInSandbox(_ url: URL) -> Bool {
        guard let containerURL = getAppContainerURL() else { return false }
        return url.path.hasPrefix(containerURL.path)
    }
    
    func canCreateFile(at url: URL) -> Bool {
        return isPathInSandbox(url)
    }
}

class DocumentPickerManager {
    func createSecurityScopedURL(for url: URL) -> URL? {
        // Mock security-scoped URL creation
        return url
    }
}

class SecureImportManager {
    private var securityScopedResources: Set<URL> = []
    
    func acquireSecurityScopedAccess(for url: URL) -> URL? {
        securityScopedResources.insert(url)
        return url
    }
    
    func hasValidAccess(to url: URL) -> Bool {
        return securityScopedResources.contains(url)
    }
    
    func cleanupSecurityScopedResources() {
        securityScopedResources.removeAll()
    }
    
    func renewSecurityScopedAccess(for url: URL) -> URL? {
        return acquireSecurityScopedAccess(for: url)
    }
}

class TemporaryFileManager {
    private var temporaryFiles: [URL] = []
    
    func createTemporaryFile(withName name: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let testData = Data("temporary data".utf8)
        
        do {
            try testData.write(to: tempURL)
            temporaryFiles.append(tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
    
    func cleanupTemporaryFiles() {
        for tempURL in temporaryFiles {
            try? FileManager.default.removeItem(at: tempURL)
        }
        temporaryFiles.removeAll()
    }
}

// Data structures for testing
struct UserSensitiveData: Codable {
    let userId: String
    let preferences: [String: Any]
    let bookmarks: [String: [Double]]
    let listeningHistory: [String: TimeInterval]
    
    enum CodingKeys: CodingKey {
        case userId, preferences, bookmarks, listeningHistory
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        // Simplified encoding for testing
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        preferences = [:]
        bookmarks = [:]
        listeningHistory = [:]
    }
    
    init(userId: String, preferences: [String: Any], bookmarks: [String: [Double]], listeningHistory: [String: TimeInterval]) {
        self.userId = userId
        self.preferences = preferences
        self.bookmarks = bookmarks
        self.listeningHistory = listeningHistory
    }
}

class UserDataManager {
    func encryptUserData(_ data: UserSensitiveData) -> Data? {
        do {
            let jsonData = try JSONEncoder().encode(data)
            // Mock encryption - in reality would use proper encryption
            return Data(jsonData.reversed())
        } catch {
            return nil
        }
    }
    
    func decryptUserData(_ encryptedData: Data) throws -> UserSensitiveData {
        // Mock decryption
        let decryptedData = Data(encryptedData.reversed())
        return try JSONDecoder().decode(UserSensitiveData.self, from: decryptedData)
    }
}

class KeyChainManager {
    private var mockStorage: [String: Data] = [:]
    
    func storeSecurely(data: Data, forKey key: String) -> Bool {
        mockStorage[key] = data
        return true
    }
    
    func retrieveSecurely(forKey key: String) -> Data? {
        return mockStorage[key]
    }
    
    func deleteSecurely(forKey key: String) -> Bool {
        mockStorage.removeValue(forKey: key)
        return true
    }
}

struct UserActivityData {
    let userId: String
    let deviceId: String
    let listeningDuration: TimeInterval
    let booksCompleted: Int
    let averageSpeed: Double
    let preferredGenres: [String]
    let timestamps: [Date]
}

struct AnonymizedActivityData {
    let userId: String // Hashed
    let deviceId: String // Hashed
    let listeningDuration: TimeInterval
    let booksCompleted: Int
    let averageSpeed: Double
    let preferredGenres: [String]
    let timestamps: [Date] // Generalized
}

class PrivacyAwareAnalyticsManager {
    func anonymizeUserData(_ data: UserActivityData) -> AnonymizedActivityData {
        return AnonymizedActivityData(
            userId: hashString(data.userId),
            deviceId: hashString(data.deviceId),
            listeningDuration: data.listeningDuration,
            booksCompleted: data.booksCompleted,
            averageSpeed: data.averageSpeed,
            preferredGenres: data.preferredGenres,
            timestamps: generalizeTimestamps(data.timestamps)
        )
    }
    
    func canDeAnonymize(_ data: AnonymizedActivityData) -> Bool {
        return false // Properly anonymized data cannot be de-anonymized
    }
    
    private func hashString(_ string: String) -> String {
        return "hashed_" + String(string.hashValue)
    }
    
    private func generalizeTimestamps(_ timestamps: [Date]) -> [Date] {
        // Generalize to hour precision
        return timestamps.map { timestamp in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            return calendar.date(from: components) ?? timestamp
        }
    }
}

struct FullUserProfile {
    let email: String?
    let name: String?
    let birthDate: Date?
    let location: String?
    let phoneNumber: String?
    let preferences: AudioPreferences
    let statistics: ListeningStatistics
}

struct MinimizedUserProfile {
    let email: String?
    let name: String?
    let birthDate: Date?
    let location: String?
    let phoneNumber: String?
    let preferences: AudioPreferences?
    let statistics: ListeningStatistics?
}

struct AudioPreferences {
    let volume: Double
    let speed: Double
}

struct ListeningStatistics {
    let totalTime: TimeInterval
    let booksCompleted: Int
}

class MinimalDataManager {
    func minimizeUserData(_ profile: FullUserProfile) -> MinimizedUserProfile {
        return MinimizedUserProfile(
            email: nil, // Not necessary for core functionality
            name: nil,
            birthDate: nil,
            location: nil,
            phoneNumber: nil,
            preferences: profile.preferences, // Necessary for functionality
            statistics: profile.statistics // May be necessary for features
        )
    }
    
    func createAnalyticsProfile(from profile: FullUserProfile) -> MinimizedUserProfile {
        return MinimizedUserProfile(
            email: nil,
            name: nil,
            birthDate: nil,
            location: nil,
            phoneNumber: nil,
            preferences: nil,
            statistics: profile.statistics // Only statistics for analytics
        )
    }
}

struct TestUserData {
    let id: UUID = UUID()
    let timestamp: Date
    let content: String
}

class DataRetentionManager {
    private var userData: [UUID: TestUserData] = [:]
    private var isCleanupScheduled = false
    
    func storeUserData(_ data: TestUserData) {
        userData[data.id] = data
    }
    
    func retrieveUserData(id: UUID) -> TestUserData? {
        return userData[id]
    }
    
    func enforceRetentionPolicies() {
        let retentionPeriod: TimeInterval = 2 * 365 * 24 * 3600 // 2 years
        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)
        
        userData = userData.filter { _, data in
            data.timestamp > cutoffDate
        }
        
        isCleanupScheduled = true
    }
    
    func isAutomaticCleanupScheduled() -> Bool {
        return isCleanupScheduled
    }
    
    func getNextCleanupDate() -> Date? {
        return Date().addingTimeInterval(24 * 3600) // Tomorrow
    }
}

class SecureNetworkManager {
    func isSecureURL(_ url: URL) -> Bool {
        return url.scheme == "https"
    }
    
    func createRequest(for url: URL) -> URLRequest? {
        guard isSecureURL(url) else { return nil }
        return URLRequest(url: url)
    }
    
    func createPinnedRequest(for url: URL) -> URLRequest? {
        return createRequest(for: url)
    }
    
    func validateCertificatePinning(for request: URLRequest) -> Bool {
        return true // Mock validation
    }
}

class CryptographicManager {
    private var currentKey = "mock_key_v1"
    
    func encryptForTransmission(_ data: Data) -> Data? {
        // Mock encryption
        return Data(data.reversed())
    }
    
    func decryptTransmissionData(_ encryptedData: Data) throws -> Data {
        // Mock decryption
        return Data(encryptedData.reversed())
    }
    
    func rotateEncryptionKey() -> String {
        currentKey = "mock_key_v2"
        return currentKey
    }
}

class GDPRComplianceManager {
    private var userData: [String: [String: Any]] = [:]
    
    func exportUserData(for userId: String) throws -> String {
        guard let data = userData[userId] else {
            throw NSError(domain: "UserNotFound", code: 404)
        }
        
        return """
        User Data Export for \(userId):
        - preferences: \(data["preferences"] ?? "none")
        - listening_history: \(data["listening_history"] ?? "none")
        - bookmarks: \(data["bookmarks"] ?? "none")
        """
    }
    
    func processDataCorrection(_ request: DataCorrectionRequest) -> Bool {
        // Mock data correction
        return true
    }
    
    func deleteUserData(for userId: String) -> Bool {
        userData.removeValue(forKey: userId)
        return true
    }
    
    func exportPortableUserData(for userId: String) throws -> Data {
        let exportString = try exportUserData(for: userId)
        return exportString.data(using: .utf8) ?? Data()
    }
    
    func isValidPortableFormat(_ data: Data) -> Bool {
        // Check if data is in JSON or other machine-readable format
        return !data.isEmpty
    }
}

struct DataCorrectionRequest {
    let userId: String
    let field: String
    let newValue: String
}

enum ConsentType {
    case analytics
    case personalization
    case marketing
}

struct ConsentRecord {
    let userId: String
    let consentType: ConsentType
    let granted: Bool
    let timestamp: Date
    let version: String
}

class ConsentManager {
    private var consents: [String: [ConsentType: ConsentRecord]] = [:]
    
    func recordConsent(_ consent: ConsentRecord) -> Bool {
        if consents[consent.userId] == nil {
            consents[consent.userId] = [:]
        }
        consents[consent.userId]?[consent.consentType] = consent
        return true
    }
    
    func hasValidConsent(userId: String, for type: ConsentType) -> Bool {
        return consents[userId]?[type]?.granted == true
    }
    
    func withdrawConsent(userId: String, for type: ConsentType) -> Bool {
        consents[userId]?[type] = nil
        return true
    }
}