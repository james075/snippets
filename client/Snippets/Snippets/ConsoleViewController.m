//
//  ConsoleViewController.m
//  Snippets
//
//  Created by James Heng on 09/12/13.
//  Copyright (c) 2013 Snippets. All rights reserved.
//

#import "ConsoleViewController.h"

#import "NSError+Redis.h"

#import "Redis.h"
#import "Command.h"

#define REDIS_PROMPT @"<div class='lg'>redis></div> %@"

#define REDIS_CMD(_CMD) [NSString stringWithFormat:REDIS_PROMPT, (_CMD)]
#define REDIS_RES(_RES) [(_RES) stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"]

@interface ConsoleViewController () <UIAlertViewDelegate>

// UI properties
@property (weak, nonatomic) IBOutlet UIWebView *webView;
@property (weak, nonatomic) IBOutlet UIView *inputContainerView;
@property (weak, nonatomic) IBOutlet UITextField *textField;

// Private properties
@property (strong, nonatomic) NSMutableArray *entries;
@property (strong, nonatomic) NSMutableArray *history;
@property (nonatomic) NSInteger currentIndex;

// Has to rethink the way to set properly the right module
// based on the choosen techno
@property (strong, nonatomic) Redis *redis;

@end

@implementation ConsoleViewController

#pragma mark - Life Cyle

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    _entries = [[NSMutableArray alloc] init];
    _history = [[NSMutableArray alloc] init];
    
    _redis = [[Redis alloc] init];
    
    _currentIndex = -1;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self reloadEntries];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    // automatic web view scroll down when switch orientation mode
    [self webViewDidFinishLoad:self.webView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

}

- (void)viewDidAppear:(BOOL)animated
{
    NSError *err = nil;
    if (![_redis open:&err]) {
        [[[UIAlertView alloc] initWithTitle:@"Error"
                                    message:@"Cannot start the Redis session"
                                   delegate:self
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
        
        return;
    }
    
    // Pre-load example commands
    for (NSString *cmd in _command.cli) {
        [self execCommand:cmd];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillChangeFrameNotification
                                                  object:nil];
    
    [_redis close];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Custom Accessors

- (void)setCommand:(Command *)command
{
    _command = command;

    [_entries addObject:_command.htmlHeader];
}

- (void)execCommand:(NSString *)cmd
{
    NSError *error;
    
    NSString *resp = [_redis exec:cmd error:&error];
    if (error) {
        resp = [error rds_message];
    }

    [_entries addObject:REDIS_CMD(cmd)];
    [_entries addObject:REDIS_RES(resp)];
    
    // Record the command into the history and clean up the prompt
    [_history addObject:cmd];

    // reset index navigation
    _currentIndex = -1;
    
    [self reloadEntries];
}

#pragma mark - Private

- (void)reloadEntries
{
    // Load the HTML template in memory
    NSString *path = [[NSBundle mainBundle] pathForResource:@"redis-cli" ofType:@"html"];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSString *tpl = [[NSString alloc] initWithData:[fileHandle readDataToEndOfFile] encoding:NSUTF8StringEncoding];

    // Recreate the full HTML with all entries
    NSString *content = [_entries componentsJoinedByString:@"<br/>"];
    NSString *html = [NSString stringWithFormat:tpl, content];
    
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)updatePromptWithIndex:(NSInteger)historyIndex
{
    if ([_history count] > 0 && historyIndex >= 0 && historyIndex <= [_history count] - 1) {
        NSString *cmd = [_history objectAtIndex:historyIndex];
        self.textField.text = cmd;
    }
}

#pragma mark - IBActions

- (IBAction)previousCmd:(id)sender
{
    if (_currentIndex == - 1) {
        _currentIndex = [_history count] - 1;
    }
    else {
        _currentIndex = (_currentIndex > 0) ? _currentIndex - 1 : 0;
    }
    
    [self updatePromptWithIndex:_currentIndex];
}

- (IBAction)nextCmd:(id)sender
{
    if (_currentIndex == - 1) {
        _currentIndex = [_history count];
    }
    else {
        _currentIndex = (_currentIndex < [_history count]) ? _currentIndex + 1 : _currentIndex;
    }
    
    if (_currentIndex == [_history count]) {
        self.textField.text = @"";
    }
    else {
        [self updatePromptWithIndex:_currentIndex];
    }
}

- (IBAction)dismissViewController:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    NSString *cmd = textField.text;
    
    if ([[cmd stringByTrimmingCharactersInSet:ws] length] == 0) {
        return NO;
    }

    [self execCommand:textField.text];

    // reset text field
    textField.text = @"";
    
    return NO;
}

#pragma mark - NSNotification

- (void)keyboardWillChange:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    UIViewAnimationCurve curve = [[userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    CGFloat duration = [[userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];

    CGRect endFrame = [[userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    endFrame = [self.view convertRect:endFrame fromView:nil];

    float height = self.inputContainerView.frame.size.height;
    float y = (endFrame.origin.y > self.view.frame.size.height) ? self.view.frame.size.height : endFrame.origin.y - height;

    [UIView animateWithDuration:duration
                          delay:0.0f
                        options:(UIViewAnimationOptions)curve
                     animations:^{
                         CGRect textFieldFrame = self.inputContainerView.frame;
                         textFieldFrame.origin.y = y;
                         self.inputContainerView.frame = textFieldFrame;
                     }
                     completion:nil];

    // set web view height depending on textfield y position
    CGRect webViewRect = self.webView.frame;
    webViewRect.size.height = y;
    
    self.webView.frame = webViewRect;
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    // automatic web view scroll down after exec cmd
    NSInteger height = [[webView stringByEvaluatingJavaScriptFromString:@"document.body.offsetHeight;"] intValue];
    NSString *javascript = [NSString stringWithFormat:@"window.scrollBy(0, %ld);", (long) height];

    [webView stringByEvaluatingJavaScriptFromString:javascript];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
